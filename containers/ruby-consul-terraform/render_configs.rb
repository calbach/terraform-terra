require "json"
require "open3"
require "base64"
require "fileutils"

def set_github_token()
  curl_cmd = [
      "curl",
      "-H", "X-Vault-Token: #{ENV.fetch("VAULT_TOKEN", "")}",
      "#{ENV.fetch("VAULT_ADDR")}/v1/secret/dsp/github/dsdejenkins2/githubtoken"
  ]
  Open3.popen3(*curl_cmd) { |stdin, stdout, stderr, wait_thread|
    response = JSON.load(stdout)
    $github_token = response["data"]["token"]
    ENV["GITHUB_TOKEN"] = $github_token
  }
end

def copy_file_from_github(path, output_file_name = nil, org = "broadinstitute", repo = "firecloud-develop", branch = "dev")
  if output_file_name.nil?
    output_file_name = File.basename(path)
  end
  set_github_token
  curl_cmd = [
      "curl",
      "-H", "Authorization: token #{$github_token}",
      "https://api.github.com/repos/#{org}/#{repo}/contents/#{path}?ref=#{branch}"
  ]
  Open3.popen3(*curl_cmd) { |stdin, stdout, stderr, wait_thread|
    response = JSON.load(stdout)
    # This GitHub endpoint seems to always return the content as a base-64-encoded string, but
    # assert that just to be safe.
    unless response["encoding"] == "base64"
      STDERR.puts "Expected content to be base64 encoded:"
      STDERR.puts JSON.pretty_generate(response)
      exit 1
    end
    content = response["content"]
    File.write(output_file_name, Base64.decode64(content))
  }
end

def activate_sa(sa_file)
  Open3.popen3("gcloud auth activate-service-account --key-file=#{sa_file}") { |stdin, stdout, stderr, wait_thread| 
    puts stdout.read
    puts stderr.read
  }
end

def render_instance_configs(instance_name, config_bucket)
  manifest = "base-configs/#{$app_name}/manifest.rb"
  overwrite_prompt = true
  $instance_name = instance_name
  render_dir = "/data/configs/#{instance_name}"
  FileUtils.mkdir_p(render_dir) unless File.exists?(render_dir)
  $base_dir = render_dir
  $output_dir = "#{render_dir}/configs"
  Dir.chdir(render_dir) do
    configure(manifest, overwrite_prompt)
  end
  Open3.popen3("gsutil rsync -r -d #{render_dir} gs://#{config_bucket}/#{instance_name}/") { |stdin, stdout, stderr, wait_thread|
    puts stdout.read
    puts stderr.read
  }
end

if __FILE__ == $0
  $base_dir = Dir.pwd
  copy_file_from_github "configure.rb"
  instances = JSON.parse(ENV.fetch("INSTANCES", "")).map {|self_link| self_link.split('/')[-1]}
  ENV["OUTPUT_DIR"] = "/dev/null" # This must be set when configure.rb is loaded but is not used
  require "/data/configure.rb"

  # Ugly hack -- the `configure.rb` script from the repo uses a function
  # called `render_ctmpl` that calls a docker container to run consul-template
  # to render files. Because we're running this script in a docker container,
  # we can't use docker that way. So instead, bake consul-template into this
  # container and override the `render_ctmpl` function with one that uses
  # consul-template locally.
  def render_ctmpl(file_name, output_file_name, tmp_dir=nil)
    if tmp_dir.nil?
      tmp_dir = (Dir.pwd.split("/") - $base_dir.split("/")) * "/"
    end
    cmd_env = {
      "VAULT_TOKEN" => ENV.fetch("VAULT_TOKEN", ""),
      "INSTANCE_TYPE" => $instance_type,
      "RUN_CONTEXT" => $run_context,
      "APP_NAME" => $app_name,
      "ENVIRONMENT" => $env,
      "INSTANCE_NAME" => $instance_name,
      "HOST_TAG" => $host_tag,
      "IMAGE" => $image,
      "TARGET_DOCKER_VERSION" => $target_docker_version,
      "VAULT_ADDR" => $vault_addr,
      "GOOGLE_PROJ" => $google_proj,
      "GOOGLE_APPS_DOMAIN" => $apps_domain,
      "GOOGLE_APPS_ORGANIZATION_ID" => $apps_organization_id,
      "GOOGLE_APPS_SUBDOMAIN" => $apps_subdomain,
      "GCS_NAME_PREFIX" => $gcs_name_prefix,
      "DNS_DOMAIN" => $dns_domain,
      "LDAP_BASE_DOMAIN" => $ldap_base_domain,
      "BUCKET_TAG" => $bucket_tag,
      "SERVICE_VERSION" => ENV.fetch("SERVICE_VERSION", ""),
      "DIR" => $fiab_dir
    }
    Open3.popen3(
      cmd_env, 
      "consul-template", 
      "-config=#{$vault_config_path}", 
      "-template=/data/configs/#{$instance_name}/#{tmp_dir}/#{file_name}:/data/configs/#{$instance_name}/#{tmp_dir}/#{output_file_name}",
      "-once"
    ) { |stdin, stdout, stderr, wait_thread|
    if wait_thread.value.success?
      puts "#{file_name} > #{output_file_name}"
      File.delete(file_name)
    else
      puts stderr.read
      $failure_rendering = true
      $failed_to_render_file_names.push(file_name)
    end
    }
  end
  activate_sa("/data/provider_sa.json")
  instances.map {|i| render_instance_configs(i, ENV.fetch("CONFIG_BUCKET")) }
end