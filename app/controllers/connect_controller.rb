class ConnectController < ApplicationController
  def index
    @project = current_project
    return unless @project

    @token = @project.api_tokens.first || @project.api_tokens.create!(name: "Auto-generated")
  end

  # Returns a self-contained Ruby setup script with token baked in
  def script
    project = current_project
    return head(:not_found) unless project

    token = project.api_tokens.first || project.api_tokens.create!(name: "Auto-generated")
    endpoint = request.base_url

    script = generate_script(
      endpoint: endpoint,
      token: token.token,
      project_name: project.name
    )

    render plain: script, content_type: "text/plain"
  end

  private

  def generate_script(endpoint:, token:, project_name:)
    <<~RUBY
      #!/usr/bin/env ruby
      # StaffOS Quick Connect
      # Run with: ruby <(curl -s #{endpoint}/connect/script)

      require "json"
      require "fileutils"
      require "yaml"

      ENDPOINT = "#{endpoint}"
      TOKEN = "#{token}"
      PROJECT = "#{project_name}"

      puts "\\n\\e[1mStaffOS Quick Connect\\e[0m"
      puts "=" * 40
      puts "Project:  \#{PROJECT}"
      puts "Endpoint: \#{ENDPOINT}"
      puts ""

      # 1. Save credentials
      cred_dir = File.expand_path("~/.staffos")
      cred_file = File.join(cred_dir, "credentials.yml")
      FileUtils.mkdir_p(cred_dir)
      File.write(cred_file, { "endpoint" => ENDPOINT, "token" => TOKEN }.to_yaml)
      File.chmod(0600, cred_file)
      puts "[OK] Credentials saved to \#{cred_file}"

      # 2. Create .staffos.yml
      config = {
        "project_name" => PROJECT,
        "repo_name" => `git remote get-url origin 2>/dev/null`.strip.then { |r|
          r.match(%r{[:/]([^/]+/[^/]+?)(?:\\.git)?$})&.[](1) || "local/\#{File.basename(Dir.pwd)}"
        },
        "api_endpoint" => ENDPOINT,
        "privacy" => {
          "upload_source" => false,
          "upload_diffs" => "metadata_only",
          "redact_secrets" => true
        }
      }

      unless File.exist?(".staffos.yml")
        File.write(".staffos.yml", config.to_yaml)
        puts "[OK] Created .staffos.yml"
      else
        puts "[--] .staffos.yml already exists, skipping"
      end

      # 3. Install Claude Code HTTP hooks
      claude_dir = ".claude"
      settings_file = File.join(claude_dir, "settings.json")
      FileUtils.mkdir_p(claude_dir)

      headers = { "X-StaffOS-Project" => PROJECT, "Authorization" => "Bearer \#{TOKEN}" }

      hooks = {
        "SessionStart" => [{
          "hooks" => [{
            "type" => "http",
            "url" => "\#{ENDPOINT}/api/v1/hooks/session_start",
            "headers" => headers,
            "timeout" => 10
          }]
        }],
        "UserPromptSubmit" => [{
          "hooks" => [{
            "type" => "http",
            "url" => "\#{ENDPOINT}/api/v1/hooks/prompt",
            "headers" => headers,
            "timeout" => 10
          }]
        }],
        "PostToolUse" => [{
          "matcher" => "Bash|Edit|Write|Read",
          "hooks" => [{
            "type" => "http",
            "url" => "\#{ENDPOINT}/api/v1/hooks/post_tool",
            "headers" => headers,
            "timeout" => 10
          }]
        }],
        "Stop" => [{
          "hooks" => [{
            "type" => "http",
            "url" => "\#{ENDPOINT}/api/v1/hooks/stop",
            "headers" => headers,
            "timeout" => 30
          }]
        }]
      }

      existing = File.exist?(settings_file) ? (JSON.parse(File.read(settings_file)) rescue {}) : {}
      existing["hooks"] = (existing["hooks"] || {}).merge(hooks)
      File.write(settings_file, JSON.pretty_generate(existing))
      puts "[OK] Claude Code hooks installed in \#{settings_file}"

      # 4. Add .staffos.yml to .gitignore if not already there
      gitignore = ".gitignore"
      if File.exist?(gitignore)
        contents = File.read(gitignore)
        unless contents.include?(".staffos.yml")
          File.open(gitignore, "a") { |f| f.puts "\\n# StaffOS local config\\n.staffos.yml" }
          puts "[OK] Added .staffos.yml to .gitignore"
        end
      end

      puts ""
      puts "\\e[32m[DONE]\\e[0m StaffOS connected!"
      puts ""
      puts "Next steps:"
      puts "  1. Start Claude Code in this directory"
      puts "  2. Work normally — events are captured automatically"
      puts "  3. Visit \#{ENDPOINT} to see your workstreams and passports"
      puts ""
    RUBY
  end
end
