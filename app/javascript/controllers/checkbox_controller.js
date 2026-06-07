import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  toggle(event) {
    const item = event.currentTarget
    const checkbox = item.querySelector(".checkbox-icon")
    const text = item.querySelector(".checkbox-text")

    item.classList.toggle("opacity-50")

    if (checkbox) {
      checkbox.classList.toggle("bg-purple")
      checkbox.classList.toggle("border-purple")
    }

    if (text) {
      text.classList.toggle("line-through")
    }
  }
}
