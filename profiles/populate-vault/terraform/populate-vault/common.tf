resource "vault_generic_secret" "common_secrets" {
  path = "${var.vault_path_prefix}/common/secrets"
  data_json = "${var.common_secrets_json}"
}

resource "vault_generic_secret" "tcell_app_id" {
  path = "${var.vault_path_prefix}/common/tcell_app_id"
  data_json = "${var.tcell_app_id}"
}

resource "vault_generic_secret" "tcell_api_key" {
  path = "${var.vault_path_prefix}/common/tcell_api_key"
  data_json = "${var.tcell_api_key}"
}

resource "vault_generic_secret" "common_ssl_crt" {
  path = "${var.vault_path_prefix}/common/server.crt"
  data_json = "${var.common_ssl_crt}"
}

resource "vault_generic_secret" "common_ssl_key" {
  path = "${var.vault_path_prefix}/common/server.key"
  data_json = "${var.common_ssl_key}"
}
