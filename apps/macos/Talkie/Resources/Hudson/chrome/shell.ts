namespace Hudson.Chrome {
  export function setButtonEnabled(root: ParentNode, action: string, enabled: boolean): void {
    const button = root.querySelector<HTMLButtonElement>(`[data-action="${action}"]`);
    if (button) button.disabled = !enabled;
  }

  export function setActiveTool(root: ParentNode, tool: string | null): void {
    root.querySelectorAll<HTMLElement>("[data-tool]").forEach((element) => {
      element.classList.toggle("active", element.getAttribute("data-tool") === tool);
    });
  }

  export function row(label: string, value: string): HTMLDivElement {
    const div = document.createElement("div");
    div.className = "inspector-row";
    div.innerHTML = `<span class="k"></span><span class="v"></span>`;
    div.querySelector(".k")!.textContent = label;
    div.querySelector(".v")!.textContent = value;
    return div;
  }
}
