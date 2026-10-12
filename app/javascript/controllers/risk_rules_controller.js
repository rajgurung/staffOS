import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "input"]

  add() {
    const pattern = this.element.querySelector("[data-field='pattern']").value.trim()
    const level = this.element.querySelector("[data-field='level']").value

    if (!pattern) return

    // Built with DOM nodes, not innerHTML, so a pattern can't inject markup.
    const row = document.createElement("div")
    row.className = "flex items-center gap-2 py-2 border-b border-panel-border last:border-0"

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = `project[risk_rules][${pattern}]`
    input.value = level

    const code = document.createElement("code")
    code.className = "text-primary text-[12px] flex-1"
    code.textContent = pattern

    const badge = document.createElement("span")
    badge.className = `text-[11px] font-semibold uppercase ${level === "high" ? "text-danger" : level === "medium" ? "text-warning" : "text-success"}`
    badge.textContent = level

    const button = document.createElement("button")
    button.type = "button"
    button.dataset.action = "risk-rules#remove"
    button.className = "text-danger text-[11px] font-semibold cursor-pointer bg-transparent border-0"
    button.textContent = "Remove"

    row.append(input, code, badge, button)
    this.listTarget.appendChild(row)
    this.element.querySelector("[data-field='pattern']").value = ""
  }

  remove(event) {
    event.currentTarget.closest("div").remove()
  }
}
