import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    setTimeout(() => {
      this.element.classList.add("opacity-0", "transition-opacity", "duration-500")
      setTimeout(() => this.element.remove(), 500)
    }, 4000)
  }

  dismiss() {
    this.element.remove()
  }
}
