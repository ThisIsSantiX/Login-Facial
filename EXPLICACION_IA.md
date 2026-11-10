# Cómo funcionan y cómo se entrenaron las redes neuronales

> Punto clave para explicarlo bien: **en este proyecto no entrenamos redes desde cero.**
> Usamos redes **preentrenadas** por equipos de investigación con millones de imágenes,
> y nuestro trabajo fue elegirlas, conectarlas en un sistema y **calibrar los umbrales**.
> Es lo que hacen casi todas las empresas (incluidos los bancos): entrenar un
> reconocedor facial desde cero exige millones de fotos etiquetadas y semanas de GPU.

## El sistema completo en 4 redes

| # | Red | Dónde corre | Qué hace | Tamaño |
|---|-----|-------------|----------|--------|
| 1 | **ML Kit Face Detection** (Google) | Teléfono | Encuentra la cara en vivo, mide el giro y si los ojos están abiertos | Pocos MB |
| 2 | **YuNet** (OpenCV) | Servidor | Detecta la cara y 5 puntos: ojos, nariz, comisuras de la boca | 230 KB |
| 3 | **SFace** (OpenCV) | Servidor | Convierte la cara en 128 números (su "huella") | 37 MB |
| 4 | **MiniFASNet** (Minivision) | Servidor | Dice si es una cara real o una foto/pantalla | 2 × 1,7 MB |

Flujo: el teléfono (red 1) guía a la persona y toma dos fotos → el servidor detecta la
cara (2), revisa que sea real (4 + paralaje 3D), saca la huella (3) y la compara con la
guardada.

---

## 1. ML Kit Face Detection — detector en tiempo real (teléfono)

- **Tipo de red:** red convolucional ligera tipo *single-shot detector*, de la familia
  de BlazeFace / MobileNet, diseñada por Google para correr en celulares.
- **Cómo se entrenó (aprendizaje supervisado):** se le mostraron cientos de miles de
  fotos donde personas marcaron a mano el rectángulo de cada cara. La red predice
  rectángulos; una **función de pérdida** mide cuánto se equivoca (posición del
  rectángulo + si hay cara o no) y el **descenso de gradiente** ajusta sus pesos para
  equivocarse menos. Se repite millones de veces.
- Además tiene "cabezas" extra entrenadas para estimar **el giro de la cabeza** (ángulos
  de Euler) y la **probabilidad de ojos abiertos** (clasificación binaria
  abierto/cerrado).
- **Por qué esta:** procesa un cuadro en pocos milisegundos incluso en gama baja.
- Google no publica el dataset exacto; es un modelo comercial gratuito.

## 2. YuNet — detector de caras (servidor)

- **Tipo:** CNN de detección sin anclas (*anchor-free*) con solo ~75 000 parámetros.
- **Dataset:** **WIDER FACE** (32 000 imágenes, 393 000 caras etiquetadas, con caras
  pequeñas, de lado, tapadas, con mala luz).
- **Entrenamiento:** supervisado. Por cada cara la red predice: probabilidad de que
  sea cara, el rectángulo y 5 puntos faciales. La pérdida combina clasificación
  (¿hay cara?), regresión del rectángulo (IoU) y regresión de los 5 puntos.
- **Autores:** Shiqi Yu y su grupo (SUSTech), publicado en OpenCV Zoo.

## 3. SFace — reconocimiento facial (servidor)

Es la red más importante: decide **quién** eres.

- **Tipo:** CNN (MobileFaceNet) que recibe la cara alineada de 112×112 píxeles y
  devuelve un **vector de 128 números** (*embedding*).
- **Idea del entrenamiento — aprendizaje métrico:** no aprende "esta es Ana"; aprende
  un **espacio** donde las fotos de la misma persona quedan cerca y las de personas
  distintas quedan lejos.
  - Se entrena como un clasificador con **miles de identidades** (millones de fotos
    de famosos de datasets públicos como CASIA-WebFace / MS-Celeb, según el paper).
  - La pérdida **SFace (Sigmoid-constrained Hypersphere Loss)** empuja los vectores a
    una esfera: acerca cada cara al "centro" de su persona y la aleja de los demás,
    pero con un límite (sigmoide) para no forzar demasiado las fotos de mala calidad
    o mal etiquetadas. Es una mejora sobre pérdidas como ArcFace.
- **Al usarla:** se quita la capa de clasificación y solo se usa el vector. Por eso
  **funciona con personas que la red nunca vio**: no necesita reentrenarse para cada
  usuario nuevo. Registrar a alguien = guardar su vector.
- **Cómo comparamos:** **similitud coseno** entre el vector del login y el guardado.
  Si es ≥ 0,363 (umbral recomendado por OpenCV) es la misma persona.
- **Paper:** Zhong et al., *"SFace: Sigmoid-Constrained Hypersphere Loss for Robust
  Face Recognition"*, IEEE Transactions on Image Processing, 2021.

## 4. MiniFASNet — anti-suplantación (servidor)

- **Tipo:** CNN muy pequeña (~0,4 millones de parámetros) que mira un recorte de 80×80
  alrededor de la cara. Usamos dos versiones con distinto recorte (2,7× y 4× el tamaño
  de la cara) y promediamos sus respuestas (*ensamble*).
- **Clases:** 3 → una es "cara real" y las otras dos son tipos de ataque (como fotos
  impresas y pantallas). Nosotros solo usamos la probabilidad de "real".
- **Entrenamiento:** supervisado, con un dataset de Minivision (no publicado) dividido
  en 3 carpetas: caras reales y dos tipos de ataque. Se entrena con la imagen completa
  y con recortes a distintas escalas, y luego se combinan los modelos.
- **Truco clave — supervisión auxiliar con Fourier:** durante el entrenamiento la red
  tiene una segunda salida que debe predecir el **espectro de frecuencias (Transformada
  de Fourier)** de la imagen. Las fotos impresas y las pantallas tienen patrones de
  frecuencia distintos a la piel real (moiré, tramas de impresión, pérdida de detalle
  fino). Obligar a la red a "ver" esas frecuencias la hace mucho mejor detectando
  ataques. Esa salida extra se descarta al usarla.
- **Lo que hicimos nosotros:** convertir los pesos de PyTorch a **ONNX** para que el
  servidor los ejecute con OpenCV sin instalar PyTorch, y **validar** que separa bien:
  fotos falsas 0,22 y 0,002; caras reales 0,91 a 1,00 (umbral 0,6).

## Lo que no es red neuronal: el paralaje 3D

Además de las redes hay un control **geométrico**: en una cara real la nariz sobresale
del plano de los ojos y la boca. Al girar la cabeza, la nariz se mueve distinto de lo
que se movería en una imagen plana. Con los 5 puntos de YuNet se calcula una
**homografía** (cómo se deformaría una foto plana) y se mide cuánto se aleja la nariz de
esa predicción. Una foto inclinada da casi 0; una cabeza real, bastante más.

---

## Cómo decirlo en una presentación (guion corto)

1. "No entrenamos desde cero; usamos **transfer learning / modelos preentrenados**,
   como hace la industria, porque entrenar un reconocedor requiere millones de caras."
2. "Las redes se entrenaron con **aprendizaje supervisado**: imágenes etiquetadas, una
   función de pérdida que mide el error y descenso de gradiente que ajusta los pesos."
3. "El reconocimiento usa **aprendizaje métrico**: la red convierte cada cara en 128
   números y personas iguales quedan cerca. Así reconoce a gente que nunca vio."
4. "Para evitar fraudes combinamos una red **anti-suplantación** (entrenada también con
   la Transformada de Fourier) con una **prueba de vida activa** (parpadeo y giro) y un
   control geométrico 3D."
5. "Nuestro aporte: la **arquitectura** (qué corre en el teléfono y qué en el servidor
   para que funcione en gama baja), la **conversión** a ONNX, y la **calibración y
   validación** de umbrales con pruebas automáticas."

## Si te preguntan "¿y si quisieran entrenar la suya?"

Se haría *fine-tuning* (ajuste fino): tomar SFace o MiniFASNet ya entrenadas y seguir
entrenándolas unas pocas épocas con fotos propias (por ejemplo, de los usuarios reales
del país, con sus cámaras de gama baja), con consentimiento. Para MiniFASNet el repo de
Minivision incluye el código de entrenamiento (`train.py` y `src/train_main.py`) y bastaría con carpetas de
fotos reales y de ataques.
