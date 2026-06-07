import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]

  toggle() {
    this.overlayTarget.classList.toggle("hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
  }

  keydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "/") {
      event.preventDefault()
      this.toggle()
    }
    if (event.key === "Escape") {
      this.close()
    }
  }

  connect() {
    this.keydownHandler = this.keydown.bind(this)
    document.addEventListener("keydown", this.keydownHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydownHandler)
  }
}
