(() => {
  const pages = [
    { id: "home", label: "首页", href: "index.html" },
    { id: "common", label: "常用", href: "common.html" },
    { id: "develop", label: "开发", href: "develop.html" },
    { id: "tools", label: "工具", href: "tools.html" }
  ];

  const activePage = document.body?.dataset.page || "home";
  const header = document.querySelector("[data-site-header]");

  if (!header) {
    return;
  }

  const container = document.createElement("div");
  container.className = "container";

  const nav = document.createElement("nav");
  nav.className = "header-menu";
  nav.setAttribute("aria-label", "主导航");

  const list = document.createElement("ul");

  pages.forEach((page) => {
    const listItem = document.createElement("li");
    const link = document.createElement("a");

    if (page.id === activePage) {
      listItem.className = "current-menu-item";
      link.setAttribute("aria-current", "page");
    }

    link.href = page.href;
    link.textContent = page.label;
    listItem.append(link);
    list.append(listItem);
  });

  nav.append(list);
  container.append(nav);
  header.replaceChildren(container);
})();
