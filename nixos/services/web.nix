# Web services configuration (Nginx + SSL)
{ config, pkgs, ... }:

{
  # Enable ACME for SSL certificates
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@localhost"; # Change this to your actual email for production
      # Use HTTP-01 challenge by default (works for most setups)
      # For DNS challenge, uncomment and configure the lines below:
      # dnsProvider = "cloudflare";
      # credentialsFile = "/var/lib/acme/credentials";
    };
    
    # Certificate configuration for localhost (development)
    certs = {
      "localhost" = {
        # Use HTTP-01 challenge for localhost development
        webroot = "/var/lib/acme/acme-challenge";
        # For production, you would specify your actual domain here
        # and potentially use DNS-01 challenge for wildcard certificates
      };
    };
  };
  
  # Enable Nginx web server
  services.nginx = {
    enable = true;
    
    # Recommended settings for security and performance
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    # Common HTTP configuration
    commonHttpConfig = ''
      # Security headers
      add_header X-Frame-Options DENY always;
      add_header X-Content-Type-Options nosniff always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; media-src 'self'; object-src 'none'; child-src 'self'; frame-src 'self'; worker-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'self';" always;
      
      # Hide Nginx version
      server_tokens off;
      
      # Rate limiting
      limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
      limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
      
      # Client settings
      client_max_body_size 100M;
      client_body_timeout 60s;
      client_header_timeout 60s;
      
      # Gzip settings
      gzip_vary on;
      gzip_min_length 1024;
      gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        application/xml
        image/svg+xml;
    '';
    
    # Virtual hosts configuration
    virtualHosts = {
      # Default server block - redirects HTTP to HTTPS
      "_" = {
        default = true;
        
        # ACME challenge location (must be accessible via HTTP)
        locations."/.well-known/acme-challenge/" = {
          root = "/var/lib/acme/acme-challenge";
          extraConfig = ''
            access_log off;
            log_not_found off;
            auth_basic off;
          '';
        };
        
        # Redirect all other HTTP traffic to HTTPS
        locations."/" = {
          return = "301 https://$host$request_uri";
        };
      };
      
      # Main server configuration (will be updated with actual domain later)
      "localhost" = {
        # Enable SSL with ACME certificates
        enableACME = true;
        forceSSL = true;
        
        # Document root for static files
        root = "/var/www/html";
        
        # Default location block
        locations."/" = {
          index = "index.html index.htm";
          tryFiles = "$uri $uri/ =404";
          
          # Security headers for static content
          extraConfig = ''
            add_header Cache-Control "public, max-age=31536000, immutable" always;
          '';
        };
        
        # API proxy location (for future services)
        locations."/api/" = {
          proxyPass = "http://127.0.0.1:3000/";
          proxyWebsockets = true;
          extraConfig = ''
            limit_req zone=api burst=20 nodelay;
            
            # Proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
        
        # Development tools location
        locations."/dev/" = {
          alias = "/var/www/dev/";
          extraConfig = ''
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
          '';
        };
        
        # Health check endpoint
        locations."/health" = {
          return = "200 'OK'";
          extraConfig = ''
            add_header Content-Type text/plain;
            access_log off;
          '';
        };
        
        # Nginx status endpoint for Prometheus monitoring
        locations."/nginx_status" = {
          extraConfig = ''
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            allow ::1;
            # Allow local network access for monitoring
            allow 192.168.0.0/16;
            allow 10.0.0.0/8;
            allow 172.16.0.0/12;
            deny all;
          '';
        };
        
        # Deny access to sensitive files
        locations."~ /\\.ht" = {
          return = "403";
        };
        
        locations."~ /\\.(git|svn)" = {
          return = "403";
        };
        
        # PHP support (if needed for development)
        locations."~ \\.php$" = {
          fastcgiParams = {
            SCRIPT_FILENAME = "$document_root$fastcgi_script_name";
          };
          extraConfig = ''
            fastcgi_pass unix:${config.services.phpfpm.pools.www.socket};
            fastcgi_index index.php;
          '';
        };
      };
    };
  };
  
  # Create web directories and ACME challenge directory
  systemd.tmpfiles.rules = [
    "d /var/www 0755 nginx nginx -"
    "d /var/www/html 0755 nginx nginx -"
    "d /var/www/dev 0755 nginx nginx -"
    "d /var/log/nginx 0755 nginx nginx -"
    "d /var/lib/acme 0755 acme acme -"
    "d /var/lib/acme/acme-challenge 0755 acme acme -"
  ];
  
  # Note: NixOS automatically handles ACME certificate renewal
  # The security.acme module creates systemd timers and services automatically
  # for certificate renewal. Manual renewal services are not needed.
  
  # Additional SSL/TLS security configuration
  services.nginx.sslCiphers = "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384";
  services.nginx.sslProtocols = "TLSv1.2 TLSv1.3";
  
  # Enable HSTS (HTTP Strict Transport Security)
  services.nginx.appendHttpConfig = ''
    # HSTS (HTTP Strict Transport Security)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    
    # SSL session settings
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
  '';
  
  # Create ACME credentials file template (user needs to fill in actual credentials)
  environment.etc."acme-credentials-template" = {
    text = ''
      # ACME DNS Provider Credentials Template
      # Copy this file to /var/lib/acme/credentials and fill in your actual credentials
      # Make sure to set proper permissions: chmod 600 /var/lib/acme/credentials
      
      # For Cloudflare (if using Cloudflare DNS)
      # CLOUDFLARE_EMAIL=your-email@example.com
      # CLOUDFLARE_API_KEY=your-global-api-key
      # OR
      # CLOUDFLARE_DNS_API_TOKEN=your-dns-api-token
      
      # For other DNS providers, check the ACME client documentation
      # Examples:
      # Route53: AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx
      # DigitalOcean: DO_AUTH_TOKEN=xxx
      # Google Cloud DNS: GCE_PROJECT=xxx GCE_SERVICE_ACCOUNT_FILE=xxx
    '';
    mode = "0644";
  };
  
  # Create default index.html
  environment.etc."var/www/html/index.html" = {
    text = ''
      <!DOCTYPE html>
      <html lang="en">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>NixOS Home Server</title>
          <style>
              body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  max-width: 800px;
                  margin: 0 auto;
                  padding: 2rem;
                  line-height: 1.6;
                  color: #333;
              }
              .header {
                  text-align: center;
                  margin-bottom: 2rem;
                  padding-bottom: 1rem;
                  border-bottom: 2px solid #eee;
              }
              .services {
                  display: grid;
                  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                  gap: 1rem;
                  margin-top: 2rem;
              }
              .service {
                  padding: 1rem;
                  border: 1px solid #ddd;
                  border-radius: 8px;
                  background: #f9f9f9;
              }
              .service h3 {
                  margin-top: 0;
                  color: #2563eb;
              }
              .status {
                  display: inline-block;
                  padding: 0.25rem 0.5rem;
                  border-radius: 4px;
                  font-size: 0.875rem;
                  font-weight: bold;
              }
              .status.running {
                  background: #dcfce7;
                  color: #166534;
              }
              .footer {
                  text-align: center;
                  margin-top: 2rem;
                  padding-top: 1rem;
                  border-top: 1px solid #eee;
                  color: #666;
                  font-size: 0.875rem;
              }
          </style>
      </head>
      <body>
          <div class="header">
              <h1>🏠 NixOS Home Server</h1>
              <p>Development-focused home server with comprehensive tooling</p>
          </div>
          
          <div class="services">
              <div class="service">
                  <h3>Web Server</h3>
                  <p><span class="status running">Running</span></p>
                  <p>Nginx with SSL support and security headers</p>
              </div>
              
              <div class="service">
                  <h3>Development Environment</h3>
                  <p><span class="status running">Ready</span></p>
                  <p>TypeScript, Java, C++, Rust, Python development tools</p>
              </div>
              
              <div class="service">
                  <h3>Remote Access</h3>
                  <p><span class="status running">Available</span></p>
                  <p>SSH and remote desktop access configured</p>
              </div>
              
              <div class="service">
                  <h3>File Sharing</h3>
                  <p><span class="status running">Active</span></p>
                  <p>Samba shares for cross-platform file access</p>
              </div>
          </div>
          
          <div class="footer">
              <p>Powered by NixOS • Configured with ❤️</p>
              <p><a href="/health">Health Check</a> | <a href="/dev/">Development Files</a></p>
          </div>
      </body>
      </html>
    '';
    mode = "0644";
  };
  
  # Optional: Enable PHP-FPM for development (commented out by default)
  # services.phpfpm.pools.www = {
  #   user = "nginx";
  #   group = "nginx";
  #   settings = {
  #     "listen.owner" = "nginx";
  #     "listen.group" = "nginx";
  #     "listen.mode" = "0600";
  #     "pm" = "dynamic";
  #     "pm.max_children" = 32;
  #     "pm.start_servers" = 2;
  #     "pm.min_spare_servers" = 2;
  #     "pm.max_spare_servers" = 4;
  #     "pm.max_requests" = 500;
  #   };
  # };
}