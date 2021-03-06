resource "null_resource" "gae_deploy" {
  triggers = {
    gae_commit = "${var.calhoun_git_commit}"
    always = "${uuid()}"
  }
  provisioner "local-exec" {
    command = "/bin/bash ${local_file.deploy_script.filename}"
  }
  depends_on = ["local_file.deploy_script", "local_file.config_py", "local_file.app_yaml", "module.enable-services"]
}
