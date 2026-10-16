require "io/console"

module AdminAccountProvisioning
  def self.console
    console = IO.console
    abort "An interactive terminal is required to manage admin accounts." unless console
    console
  end

  def self.read_email(console)
    console.print "Email: "
    email = console.gets&.strip
    abort "Email is required." if email.blank?
    email
  end

  def self.read_confirmed_password(console, password: nil)
    password ||= console.getpass("Password (at least 12 characters): ")
    confirmation = console.getpass("Confirm password: ")
    abort "Passwords do not match." unless password == confirmation
    password
  end
end

namespace :admin do
  desc "Create an administrator account"
  task create: :environment do
    console = AdminAccountProvisioning.console
    email = AdminAccountProvisioning.read_email(console)
    password = AdminAccountProvisioning.read_confirmed_password(console)

    AdminUser.create!(email:, password:)
    puts "Admin account created."
  end

  desc "Reset an administrator password"
  task reset_password: :environment do
    console = AdminAccountProvisioning.console
    email = AdminAccountProvisioning.read_email(console)
    password = console.getpass("Password (at least 12 characters): ")
    password = AdminAccountProvisioning.read_confirmed_password(console, password:)

    admin_user = AdminUser.find_by!(email: email.downcase)
    admin_user.update!(password:)
    puts "Admin password reset."
  end
end
