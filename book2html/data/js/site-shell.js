(() => {
  const header = document.querySelector("[data-site-header]");
  if (!header) return;

  const container = document.createElement("div");
  container.className = "container";

  const nav = document.createElement("nav");
  nav.className = "header-menu";
  nav.setAttribute("aria-label", "收藏导航");

  const list = document.createElement("ul");
  nav.append(list);
  container.append(nav);
  header.replaceChildren(container);
})();
