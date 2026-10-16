import { Controller } from "@hotwired/stimulus"
import { loadStripe } from "@stripe/stripe-js"

export default class extends Controller {
  static values = {
    clientSecret: String,
    publishableKey: String,
    returnUrl: String
  }

  static targets = [ "element", "error", "submit" ]

  async connect() {
    try {
      this.stripe = await loadStripe(this.publishableKeyValue)
      if (!this.stripe) {
        this.showError("Secure payment could not be loaded. Refresh the page to try again.")
        this.submitTarget.disabled = true
        return
      }

      this.elements = this.stripe.elements({ clientSecret: this.clientSecretValue })
      this.elements.create("payment").mount(this.elementTarget)
    } catch (error) {
      this.showError(error.message || "Secure payment could not be loaded. Refresh the page to try again.")
      this.submitTarget.disabled = true
    }
  }

  async submit(event) {
    event.preventDefault()
    if (!this.stripe || !this.elements) {
      this.showError("Secure payment is not ready. Refresh the page to try again.")
      return
    }

    this.submitTarget.disabled = true
    this.showError("")

    try {
      const { error, paymentIntent } = await this.stripe.confirmPayment({
        elements: this.elements,
        confirmParams: { return_url: this.returnUrlValue },
        redirect: "if_required"
      })

      if (error) {
        this.showError(error.message || "Payment could not be completed.")
        this.submitTarget.disabled = false
        return
      }

      if (paymentIntent?.status === "succeeded") {
        window.location.assign(this.returnUrlValue)
      }
    } catch (error) {
      this.showError(error.message || "Payment could not be completed. Try again.")
      this.submitTarget.disabled = false
    }
  }

  showError(message) {
    this.errorTarget.textContent = message
  }
}
