const siteHeader = document.querySelector('.site-header');
const navToggle = document.querySelector('.nav-toggle');
const siteNav = document.getElementById('site-nav');
const navLinks = Array.from(siteNav.querySelectorAll('a'));
const sections = navLinks
  .map((link) => document.querySelector(link.hash))
  .filter(Boolean);

function closeNav(restoreFocus = false) {
  if (!siteNav.classList.contains('is-open')) return;
  siteNav.classList.remove('is-open');
  navToggle.setAttribute('aria-expanded', 'false');
  navToggle.setAttribute('aria-label', 'Abrir menú de navegación');
  if (restoreFocus) navToggle.focus();
}

function openNav() {
  siteNav.classList.add('is-open');
  navToggle.setAttribute('aria-expanded', 'true');
  navToggle.setAttribute('aria-label', 'Cerrar menú de navegación');
}

navToggle.addEventListener('click', () => {
  if (siteNav.classList.contains('is-open')) closeNav();
  else openNav();
});

navLinks.forEach((link) => link.addEventListener('click', () => closeNav()));

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && siteNav.classList.contains('is-open')) closeNav(true);
});

document.addEventListener('click', (event) => {
  if (
    siteNav.classList.contains('is-open') &&
    !siteNav.contains(event.target) &&
    !navToggle.contains(event.target)
  ) closeNav();
});

const rootStyles = getComputedStyle(document.documentElement);
const staggerStep = parseFloat(rootStyles.getPropertyValue('--stagger-step')) || 60;
const staggerMax = parseFloat(rootStyles.getPropertyValue('--stagger-max')) || 240;
const scrollElevationOffset = 8;

let activeId = sections[0]?.id;

function updateActiveLink() {
  const marker = window.scrollY + Math.min(window.innerHeight * 0.35, 240);
  activeId = sections[0]?.id;

  sections.forEach((section) => {
    if (section.offsetTop <= marker) activeId = section.id;
  });

  navLinks.forEach((link) => {
    const isActive = link.hash === `#${activeId}`;
    link.classList.toggle('is-active', isActive);
    if (isActive) link.setAttribute('aria-current', 'location');
    else link.removeAttribute('aria-current');
  });
}

let scrollQueued = false;

window.addEventListener('scroll', () => {
  if (scrollQueued) return;
  scrollQueued = true;
  requestAnimationFrame(() => {
    updateActiveLink();
    siteHeader.classList.toggle('is-scrolled', window.scrollY > scrollElevationOffset);
    scrollQueued = false;
  });
}, { passive: true });

window.addEventListener('resize', () => {
  if (window.innerWidth > 760) closeNav();
  updateActiveLink();
});

updateActiveLink();
siteHeader.classList.toggle('is-scrolled', window.scrollY > scrollElevationOffset);

document.querySelectorAll('[data-reveal-group]').forEach((group) => {
  Array.from(group.children)
    .filter((child) => child.hasAttribute('data-reveal'))
    .forEach((child, index) => {
      const delay = Math.min(index * staggerStep, staggerMax);
      child.style.setProperty('--reveal-delay', `${delay}ms`);
    });
});

const revealTargets = document.querySelectorAll('[data-reveal]');

if ('IntersectionObserver' in window) {
  const revealObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

  revealTargets.forEach((target) => revealObserver.observe(target));
} else {
  revealTargets.forEach((target) => target.classList.add('is-visible'));
}
