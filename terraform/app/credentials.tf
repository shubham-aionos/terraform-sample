resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?@^_"
}
