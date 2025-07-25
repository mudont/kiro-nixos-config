# Web services configuration (Nginx + SSL)
{ config, pkgs, ... }:

{
  # Enable Nginx web server
  services.nginx = {
    enable = true;
    
    # Basic recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    # Virtual hosts configuration
    virtualHosts = {
      # Default server (localhost)
      "localhost" = {
        default = true;
        root = "/var/www/html";
        
        # Basic locations
        locations = {
          "/" = {
            index = "index.html index.htm";
            tryFiles = "$uri $uri/ =404";
          };
          
          # Health check endpoint
          "/health" = {
            return = "200 'OK'";
            extraConfig = ''
              access_log off;
              add_header Content-Type text/plain;
            '';
          };
        };
      };
    };
  };
  
  # TODO: Enable ACME/SSL when router is configured
  # Currently commented out to prevent certificate errors
  # 
  # security.acme = {
  #   acceptTerms = true;
  #   defaults.email = "your-email@example.com";
  #   certs = {
  #     "localhost" = {
  #       webroot = "/var/lib/acme/acme-challenge";
  #       extraDomainNames = [ "www.localhost" ];
  #     };
  #   };
  # };
  
  # Create web directories
  systemd.tmpfiles.rules = [
    "d /var/www 0755 nginx nginx -"
    "d /var/www/html 0755 nginx nginx -"
    "d /var/www/dev 0755 nginx nginx -"
  ];
  
  # Create default index pages
  systemd.services.nginx-setup = {
    description = "Setup Nginx default pages";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    script = ''
      # Create default index page
      cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>NixOS Home Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        .service { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #007acc; }
        .status { color: #28a745; font-weight: bold; }
        a { color: #007acc; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏠 NixOS Home Server</h1>
        <p>Welcome to your NixOS home server! This system provides development tools, file sharing, and monitoring capabilities.</p>
        
        <h2>📊 Services</h2>
        <div class="service">
            <h3>Monitoring Dashboard</h3>
            <p><span class="status">●</span> <a href="http://localhost:3000">Grafana Dashboard</a> - System monitoring and metrics</p>
        </div>
        
        <div class="service">
            <h3>Development Environment</h3>
            <p><span class="status">●</span> Full development stack with TypeScript, Java, C++, Rust, Python</p>
            <p><span class="status">●</span> Docker and Podman container support</p>
            <p><span class="status">●</span> PostgreSQL database available on localhost:5432</p>
        </div>
        
        <div class="service">
            <h3>File Sharing</h3>
            <p><span class="status">●</span> Samba shares available for Mac/iPhone access</p>
            <p><span class="status">●</span> Connect to: <code>smb://nixos/public-share</code></p>
        </div>
        
        <div class="service">
            <h3>Remote Access</h3>
            <p><span class="status">●</span> XFCE desktop via RDP on port 3389</p>
            <p><span class="status">●</span> SSH access available on port 22</p>
        </div>
        
        <h2>🔧 System Information</h2>
        <p>Hostname: <code>nixos</code></p>
        <p>Configuration: NixOS with Flakes</p>
        <p>Last updated: $(date)</p>
        
        <h2>📚 Quick Links</h2>
        <ul>
            <li><a href="/health">Health Check</a></li>
            <li><a href="http://localhost:3000">Grafana Monitoring</a></li>
            <li><a href="http://localhost:9090">Prometheus Metrics</a></li>
        </ul>
    </div>
</body>
</html>
EOF
      
      # Create development index page
      cat > /var/www/dev/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Development Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #1a1a1a; color: #e0e0e0; }
        .container { max-width: 800px; margin: 0 auto; background: #2d2d2d; padding: 30px; border-radius: 8px; }
        h1 { color: #61dafb; border-bottom: 2px solid #61dafb; padding-bottom: 10px; }
        .service { background: #3a3a3a; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #61dafb; }
        .status { color: #4caf50; font-weight: bold; }
        a { color: #61dafb; text-decoration: none; }
        a:hover { text-decoration: underline; }
        code { background: #1a1a1a; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Development Environment</h1>
        <p>Development server for testing and building applications.</p>
        
        <div class="service">
            <h3>Available Languages & Tools</h3>
            <ul>
                <li>Node.js 20 LTS with TypeScript</li>
                <li>Java 21 with Maven & Gradle</li>
                <li>C++ with GCC & Clang</li>
                <li>Rust with Cargo</li>
                <li>Python 3.12 with Poetry</li>
            </ul>
        </div>
        
        <div class="service">
            <h3>Container Support</h3>
            <ul>
                <li>Docker with Docker Compose</li>
                <li>Podman with Podman Compose</li>
            </ul>
        </div>
        
        <div class="service">
            <h3>Database</h3>
            <p>PostgreSQL available at <code>localhost:5432</code></p>
            <p>Development databases: development, testing, staging</p>
        </div>
        
        <p><em>This page is served from /var/www/dev</em></p>
    </div>
</body>
</html>
EOF
      
      # Set proper permissions
      chown -R nginx:nginx /var/www
      chmod -R 755 /var/www
    '';
  };
}