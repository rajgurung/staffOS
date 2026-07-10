require "test_helper"

class LandingPageTest < ActionDispatch::IntegrationTest
  test "guests see the landing page" do
    get root_path
    assert_response :success
    assert_select "h1", /StaffOS writes the receipts/
    assert_select "a[href=?]", new_user_session_path
  end

  test "signed-in users are redirected to the dashboard" do
    user = User.create!(email: "landing-test@example.com", name: "Test", password: "password123")
    sign_in user
    get root_path
    assert_redirected_to dashboard_path
  end
end
