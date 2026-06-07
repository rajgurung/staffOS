import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  copy() {
    const text = this.textValue || this.element.innerText
    navigator.clipboard.writeText(text).then(() => {
      const btn = this.element.querySelector("[data-action='clipboard#copy']")
      if (btn) {
        const original = btn.textContent
        btn.textContent = "Copied!"
        setTimeout(() => { btn.textContent = original }, 2000)
      }
    })
  }
}
