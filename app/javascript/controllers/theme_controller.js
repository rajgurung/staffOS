import { Controller } from "@hotwired/stimulus"

// Theme toggle. data-theme lives on <html>, which Turbo never replaces, so
// the theme persists across navigations; connect() re-syncs the button icon
// after Turbo restores a cached <body>.
export default class extends Controller {
  static targets = ["sun", "moon"]

  connect() {
    this.syncIcons()
  }

  toggle() {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem("staffos_theme", next) } catch (e) {}
    document.cookie = `staffos_theme=${next};path=/;max-age=31536000;SameSite=Lax`
    this.syncIcons()
  }

  syncIcons() {
    const dark = document.documentElement.dataset.theme === "dark"
    if (this.hasSunTarget) this.sunTarget.classList.toggle("hidden", !dark)
    if (this.hasMoonTarget) this.moonTarget.classList.toggle("hidden", dark)
  }
}
