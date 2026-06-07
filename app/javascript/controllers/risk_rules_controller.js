import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "input"]

  add() {
    const pattern = this.element.querySelector("[data-field='pattern']").value.trim()
    const level = this.element.querySelector("[data-field='level']").value

    if (!pattern) return

    const row = document.createElement("div")
    row.className = "flex items-center gap-2 py-2 border-b border-panel-border last:border-0"
    row.innerHTML = `
      <input type="hidden" name="project[risk_rules][${pattern}]" value="${level}" />
      <code class="text-primary text-[12px] flex-1">${pattern}</code>
      <span class="text-[11px] font-semibold uppercase ${level === 'high' ? 'text-danger' : level === 'medium' ? 'text-warning' : 'text-success'}">${level}</span>
      <button type="button" data-action="risk-rules#remove" class="text-danger text-[11px] font-semibold cursor-pointer bg-transparent border-0">Remove</button>
    `
    this.listTarget.appendChild(row)
    this.element.querySelector("[data-field='pattern']").value = ""
  }

  remove(event) {
    event.currentTarget.closest("div").remove()
  }
}
