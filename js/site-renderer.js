(() => {
  const pageId = document.body?.dataset.page || "home";
  const mount = document.querySelector("[data-nav-page]");
  const pageData = window.SITE_DATA?.[pageId];

  if (!mount || !pageData) {
    return;
  }

  const createText = (tagName, className, text) => {
    const element = document.createElement(tagName);
    element.className = className;
    element.textContent = text;
    return element;
  };

  const renderItem = (item) => {
    const listItem = document.createElement("li");
    const link = document.createElement("a");
    const icon = document.createElement("img");

    link.className = "nav-item clearfix";
    link.href = item.url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.setAttribute("aria-label", item.description ? `${item.name}：${item.description}` : item.name);

    if (item.description) {
      link.classList.add("has-description");
    }

    icon.className = "nav-img";
    icon.src = item.icon;
    icon.alt = "";
    icon.loading = "lazy";
    icon.decoding = "async";

    link.append(icon, createText("div", "nav-name", item.name));

    if (item.description) {
      link.append(createText("p", "", item.description));
    }

    listItem.append(link);
    return listItem;
  };

  const renderSection = (section, index) => {
    const sectionElement = document.createElement("section");
    const list = document.createElement("ul");
    const titleId = `${pageId}-section-${index}`;

    sectionElement.className = "nav-cell clearfix";
    list.className = "nav-list";

    if (section.title) {
      const heading = createText("h2", "nav-section-title", section.title);
      heading.id = titleId;
      sectionElement.setAttribute("aria-labelledby", titleId);
      sectionElement.append(heading);
    } else {
      sectionElement.setAttribute("aria-label", `${pageData.title}导航`);
    }

    section.items.forEach((item) => list.append(renderItem(item)));
    sectionElement.append(list);
    return sectionElement;
  };

  const fragment = document.createDocumentFragment();

  pageData.sections.forEach((section, index) => {
    fragment.append(renderSection(section, index));
  });

  mount.replaceChildren(fragment);
})();
