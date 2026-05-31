(() => {
  const scriptUrl = document.currentScript && document.currentScript.src ? document.currentScript.src : "";
  const resolveImageUrl = (fileName) => {
    if (scriptUrl) {
      return new URL(`../images/${fileName}`, scriptUrl).href;
    }

    return new URL(`images/${fileName}`, window.location.href).href;
  };
  const fallbackBackgroundUrl = resolveImageUrl("beijing.jpg");
  const themeBackgrounds = {
    default: resolveImageUrl("theme-bg-glass.jpg"),
    dark: resolveImageUrl("theme-bg-obsidian.jpg"),
    glass: resolveImageUrl("theme-bg-glass.jpg"),
    liquid: resolveImageUrl("theme-bg-liquid.jpg"),
    "liquid-lite": resolveImageUrl("theme-bg-liquid-lite.jpg"),
    acrylic: resolveImageUrl("theme-bg-acrylic.jpg"),
    mica: resolveImageUrl("theme-bg-mica.jpg"),
    paper: resolveImageUrl("theme-bg-paper.jpg"),
    obsidian: resolveImageUrl("theme-bg-obsidian.jpg"),
    neon: resolveImageUrl("theme-bg-neon.jpg"),
    pixel: resolveImageUrl("theme-bg-pixel.jpg"),
    plain: resolveImageUrl("theme-bg-plain.jpg")
  };
  const body = document.body;
  let requestId = 0;

  if (!body) {
    return;
  }

  const getPreferredBackgroundUrl = () => {
    if (body.dataset.themeBackgroundPriority === "simple") {
      return null;
    }

    if (body.dataset.themeBackgroundPriority !== "on") {
      return fallbackBackgroundUrl;
    }

    const surface = body.dataset.surface;

    if (surface && themeBackgrounds[surface]) {
      return themeBackgrounds[surface];
    }

    return body.dataset.theme === "dark" ? themeBackgrounds.dark : themeBackgrounds.default;
  };

  const applyBackground = () => {
    const currentRequest = ++requestId;
    const backgroundUrl = getPreferredBackgroundUrl();
    const setBackground = (url) => {
      if (currentRequest !== requestId) {
        return;
      }

      body.style.setProperty("--site-background-image", `url("${url}")`);
    };

    if (!backgroundUrl) {
      body.style.setProperty("--site-background-image", "none");
      return;
    }

    if (backgroundUrl === fallbackBackgroundUrl) {
      setBackground(fallbackBackgroundUrl);
      return;
    }

    const image = new Image();
    image.src = backgroundUrl;
    image.decoding = "async";

    if ("fetchPriority" in image) {
      image.fetchPriority = backgroundUrl === fallbackBackgroundUrl ? "high" : "auto";
    }

    if (typeof image.decode === "function") {
      image.decode().then(() => setBackground(backgroundUrl)).catch(() => setBackground(fallbackBackgroundUrl));
      return;
    }

    image.onload = () => setBackground(backgroundUrl);
    image.onerror = () => setBackground(fallbackBackgroundUrl);
  };

  applyBackground();

  new MutationObserver(applyBackground).observe(body, {
    attributes: true,
    attributeFilter: ["data-theme", "data-surface", "data-theme-background-priority"]
  });
})();
