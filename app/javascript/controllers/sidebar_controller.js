import { Controller } from "@hotwired/stimulus"

// Off-canvas mobile navigation drawer. On desktop the sidebar is always
// visible (CSS), so these actions are only wired up on small screens.
export default class extends Controller {
  static targets = ["panel", "backdrop"]

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Close when a nav link is tapped so the drawer doesn't linger over the page.
  closeOnNavigate(event) {
    if (event.target.closest("a")) this.close()
  }
}
