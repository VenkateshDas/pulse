// Three.js animates only this semantic DOM panel; values never change or sample the host.
const host = document.querySelector('.indicator-scene');
const board = host.querySelector('.indicator-board');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let stop;
let refresh;
let loading = false;
let nearViewport = false;
let motionAllowed = true;
let printing = false;
const initialPixelRatio = devicePixelRatio;

async function start() {
  if (printing || !motionAllowed || stop || loading || reducedMotion.matches || document.hidden || !nearViewport || !CSS.supports("transform-style", "preserve-3d")) return;
  loading = true;
  try {
    const { Scene, PerspectiveCamera, MathUtils, CSS3DRenderer, CSS3DObject } =
      await import('./vendor/pulse-three.js');
    if (printing || !motionAllowed || reducedMotion.matches || !nearViewport || document.hidden) return;
    const originalStyle = board.getAttribute('style');
    const scene = new Scene();
    const camera = new PerspectiveCamera(40, 1, 1, 3000);
    const renderer = new CSS3DRenderer();
    renderer.domElement.className = 'indicator-renderer';
    const panel = new CSS3DObject(board);
    board.style.userSelect = "text";
    scene.add(panel);
    host.append(renderer.domElement);
    let frame = 0;
    let disposed = false;
    let width = 0;
    let height = 0;

    function draw() {
      frame = 0;
      if (disposed || reducedMotion.matches || document.hidden || !nearViewport) return;
      const bounds = host.getBoundingClientRect();
      if (bounds.bottom <= 0 || bounds.top >= innerHeight) return;
      if (width !== bounds.width || height !== bounds.height) {
        width = bounds.width;
        height = bounds.height;
        renderer.setSize(width, height);
        camera.aspect = width / height;
        camera.position.z = height / (2 * Math.tan(MathUtils.degToRad(20)));
        camera.updateProjectionMatrix();
      }
      // Independent readings settle into one plane as the overview enters view.
      const progress = MathUtils.clamp((innerHeight * 0.8 - bounds.top) / (innerHeight * 0.65), 0, 1);
      const remaining = Math.pow(1 - progress, 3);
      panel.rotation.set(MathUtils.degToRad(8 * remaining), MathUtils.degToRad(-7 * remaining), MathUtils.degToRad(-1.5 * remaining));
      renderer.render(scene, camera);
    }
    function requestDraw() {
      if (!frame && !disposed && nearViewport && !document.hidden) frame = requestAnimationFrame(draw);
    }
    const resize = new ResizeObserver(() => {
      if (nearViewport) requestDraw();
      else stop?.();
    });
    resize.observe(host);
    window.addEventListener('scroll', requestDraw, { passive: true });
    document.addEventListener('visibilitychange', requestDraw);
    refresh = requestDraw;
    stop = () => {
      disposed = true;
      cancelAnimationFrame(frame);
      resize.disconnect();
      window.removeEventListener('scroll', requestDraw);
      document.removeEventListener('visibilitychange', requestDraw);
      host.append(board);
      if (originalStyle === null) board.removeAttribute('style');
      else board.setAttribute('style', originalStyle);
      renderer.domElement.remove();
      stop = undefined;
      refresh = undefined;
    };
    requestDraw();
  } catch {
    // The original readable panel is the fallback; no content depends on Three.js.
  } finally {
    loading = false;
  }
}
const observer = new IntersectionObserver(([entry]) => {
  nearViewport = entry.isIntersecting;
  if (nearViewport) {
    if (stop) refresh?.();
    else start();
  }
}, { rootMargin: '200px' });
observer.observe(host);
reducedMotion.addEventListener('change', () => {
  if (reducedMotion.matches) stop?.();
  else start();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden) start(); });
window.addEventListener('pagehide', () => stop?.());
window.addEventListener('pageshow', start);

window.addEventListener("beforeprint", () => { printing = true; stop?.(); });
window.addEventListener("afterprint", () => { printing = false; start(); });

// CSS3DRenderer expects normal zoom. Keep text in normal flow after zoom changes.
function checkZoom() {
  if (devicePixelRatio !== initialPixelRatio || (window.visualViewport && window.visualViewport.scale !== 1)) {
    motionAllowed = false;
    stop?.();
  }
}
window.addEventListener('resize', checkZoom);
window.visualViewport?.addEventListener('resize', checkZoom);
checkZoom();
