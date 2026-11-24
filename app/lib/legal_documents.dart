const legalOwner = 'Wanda.dev';
const legalEmail = 'industrial31@unisalamanca.edu.co';
const legalLocation = 'Barranquilla, Colombia';
const legalEffectiveDate = '23 de noviembre de 2026';
const legalVersion = '2026-11-23-v1';

const privacyTitle = 'Política de Privacidad';
const termsTitle = 'Términos y Condiciones';

class LegalSection {
  const LegalSection(this.title, this.body);

  final String title;
  final String body;
}

const privacySections = <LegalSection>[
  LegalSection(
    '1. Responsable del tratamiento',
    'Wanda.dev, con domicilio en Barranquilla, Colombia, es responsable del tratamiento de los datos personales recogidos por esta aplicación. Puedes contactar al responsable en industrial31@unisalamanca.edu.co.',
  ),
  LegalSection(
    '2. Datos que recogemos',
    'Al registrarte recogemos tu nombre de usuario, un PIN que se almacena como hash PBKDF2 con salt aleatorio, dos fotografías del rostro tomadas en el momento del registro o del acceso, una plantilla biométrica de 128 valores numéricos derivada de esas fotos, un token de sesión y el registro de tu consentimiento. No solicitamos tu nombre real: el campo mostrado como nombre completo se iguala al nombre de usuario. En el teléfono se guardan localmente el token de sesión y una copia del consentimiento.',
  ),
  LegalSection(
    '3. Para qué los usamos',
    'Usamos estos datos para crear y autenticar tu cuenta, comprobar que eres una persona real mediante dos capturas y detección de vida, comparar tu rostro con la plantilla guardada, mantener tu sesión, registrar intentos de acceso y permitirte ejercer tus derechos. Solo si marcas la casilla opcional podremos usar en el futuro una copia seudonimizada de la plantilla para mejorar los modelos.',
  ),
  LegalSection(
    '4. Consentimiento',
    'Para crear una cuenta debes aceptar estos Términos y Condiciones y esta Política de Privacidad. Ese consentimiento queda asociado a tu registro con la versión del documento y la fecha. La opción de mejora de inteligencia artificial es voluntaria, no viene marcada y puede revocarse desde la aplicación o escribiendo al correo de contacto.',
  ),
  LegalSection(
    '5. Datos biométricos',
    'Los datos biométricos son datos sensibles. El detector facial en tiempo real corre dentro de tu dispositivo con ML Kit; esta aplicación no envía video ni imágenes del escáner a Google. Las dos fotos se envían al servidor para detectar el rostro, revisar la prueba de vida y calcular la plantilla. En operación normal esas fotos no se conservan; si se activa una configuración de depuración en el servidor, el último par podría guardarse temporalmente para diagnóstico. La plantilla se guarda en SQLite sin cifrado en reposo, por lo que debes usar la aplicación solo en dispositivos y servidores de confianza.',
  ),
  LegalSection(
    '6. Mejora de inteligencia artificial',
    'Hoy no entrenamos modelos con datos de usuarios. Si marcas la casilla opcional, se guarda una copia de la plantilla de 128 números en una tabla separada, acompañada de un identificador seudonímico, sin tu nombre de usuario, tu PIN ni tus fotografías. Esa copia solo podrá utilizarse para futuras mejoras y se borrará si revocas el permiso. Seudonímico reduce la identificación directa, pero no elimina todos los riesgos de reidentificación.',
  ),
  LegalSection(
    '7. Destinatarios',
    'No hemos integrado analítica ni servicios de terceros que reciban datos desde la aplicación. Los modelos preentrenados proceden de Google, OpenCV y Minivision, pero este código no envía tus datos a esos proveedores. Si en el futuro se contrata un proveedor de alojamiento u otros servicios, actuará bajo las instrucciones del responsable y esta política se actualizará.',
  ),
  LegalSection(
    '8. Conservación',
    'La sesión caduca a los 7 días y se elimina al cerrar sesión o cuando expira. Los datos de la cuenta y la plantilla se conservan mientras la cuenta permanezca activa. Las muestras destinadas a mejora de IA se conservan mientras el permiso esté activo. Los registros del servidor pueden conservarse según la configuración del alojamiento. Actualmente no existe un botón de borrado automático de cuenta; puedes solicitarlo al correo de contacto.',
  ),
  LegalSection(
    '9. Seguridad',
    'El PIN se almacena con PBKDF2 y salt aleatorio. La conexión debe usar HTTPS en producción; la configuración de desarrollo actual emplea HTTP y no debe utilizarse con datos reales fuera de una red controlada. La detección de vida reduce, pero no elimina, las suplantaciones con fotografías, pantallas o máscaras. Ningún sistema biométrico es infalible.',
  ),
  LegalSection(
    '10. Tus derechos',
    'Puedes solicitar conocimiento, actualización, rectificación, eliminación, revocación del consentimiento y abstención de tratamientos, conforme a la Ley 1581 de 2012 y la normativa reglamentaria colombiana de protección de datos. Escribe a industrial31@unisalamanca.edu.co; te pediremos verificar tu identidad antes de atender la solicitud.',
  ),
  LegalSection(
    '11. Menores de edad',
    'Este servicio no está dirigido a menores de 18 años. Si consideras que un menor ha creado una cuenta, escríbenos al correo de contacto para que podamos revisarla.',
  ),
  LegalSection(
    '12. Cambios en esta política',
    'Esta política entra en vigor el 23 de noviembre de 2026, versión 2026-11-23-v1. Cualquier cambio se publicará en esta pantalla y podría requerir una nueva aceptación.',
  ),
  LegalSection(
    '13. Contacto',
    'Responsable: Wanda.dev. Correo: industrial31@unisalamanca.edu.co. Ubicación: Barranquilla, Colombia.',
  ),
];

const termsSections = <LegalSection>[
  LegalSection(
    '1. Aceptación',
    'Al crear una cuenta aceptas estos Términos y Condiciones, versión 2026-11-23-v1, y la Política de Privacidad. Si no estás de acuerdo, no utilices la aplicación.',
  ),
  LegalSection(
    '2. El servicio',
    'Wanda.dev ofrece una demostración de inicio de sesión con reconocimiento facial y PIN. El servicio puede cambiar, interrumpirse o dejar de estar disponible sin obligación de mantener versiones anteriores.',
  ),
  LegalSection(
    '3. Tu cuenta',
    'Debes proporcionar un nombre de usuario válido y un PIN de 4 dígitos. Eres responsable de mantener tu PIN en secreto y de todas las actividades realizadas desde tu cuenta. Debes tener al menos 18 años para registrarte.',
  ),
  LegalSection(
    '4. Registro biométrico',
    'El registro requiere dos fotos del rostro y tu aceptación expresa del tratamiento de datos biométricos. La aplicación guía la captura y el servidor decide si la muestra es válida. Wanda.dev puede rechazar registros que no cumplan las comprobaciones de calidad o prueba de vida.',
  ),
  LegalSection(
    '5. Uso permitido',
    'Te comprometes a no usar la aplicación para suplantar a otras personas, eludir controles de seguridad, realizar pruebas automatizadas no autorizadas, alterar el servicio, invertir su funcionamiento o intentar acceder a cuentas ajenas.',
  ),
  LegalSection(
    '6. Mejora de IA opcional',
    'La casilla de mejora de inteligencia artificial es opcional y no viene marcada. Si la activas, autorizas el uso futuro de una copia seudonimizada de tu plantilla biométrica, sin fotos, usuario ni PIN, según lo descrito en la Política de Privacidad. Puedes revocarla desde la aplicación o escribiendo al correo de contacto.',
  ),
  LegalSection(
    '7. Propiedad intelectual',
    'La aplicación, su diseño, su lógica y los modelos integrados pertenecen a sus respectivos titulares. No se concede ninguna licencia para copiar, modificar, distribuir o crear obras derivadas sin autorización.',
  ),
  LegalSection(
    '8. Limitaciones',
    'El servicio se ofrece con fines demostrativos y no garantiza disponibilidad continua ni seguridad absoluta. La biometría puede fallar o ser burlada; la configuración de desarrollo usa HTTP y no debe considerarse apta para datos sensibles reales.',
  ),
  LegalSection(
    '9. Responsabilidad',
    'En la medida permitida por la ley colombiana, Wanda.dev no responde por daños derivados del uso indebido de la aplicación, de la pérdida del PIN o de fallos del dispositivo o de la red.',
  ),
  LegalSection(
    '10. Suspensión y terminación',
    'Podemos suspender o cancelar cuentas que incumplan estos términos, presenten intentos de acceso sospechosos o representen un riesgo para el servicio u otros usuarios.',
  ),
  LegalSection(
    '11. Ley aplicable',
    'Estos términos se rigen por las leyes de Colombia. Para cualquier controversia, las partes se someten a los tribunales competentes de Barranquilla, Colombia.',
  ),
  LegalSection(
    '12. Contacto',
    'Puedes escribir a industrial31@unisalamanca.edu.co para consultas sobre estos términos, revocación de permisos o solicitudes relacionadas con tus datos.',
  ),
];
