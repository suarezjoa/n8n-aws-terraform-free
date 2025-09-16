# Configuración del proveedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configuración del proveedor
provider "aws" {
  region = "us-east-1"
}

# Data source para obtener la AMI más reciente de Amazon Linux 2023
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Crear un par de claves (key pair) para SSH
resource "aws_key_pair" "n8n_key" {
  key_name   = "n8n-automation-key"
  public_key = file("~/.ssh/id_rsa.pub") # Ruta a tu clave pública SSH
}

# Crear grupo de seguridad
resource "aws_security_group" "n8n_sg" {
  name        = "n8n-automation-sg"
  description = "Security group for n8n automation server"

  # SSH desde cualquier lugar
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP desde cualquier lugar
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS desde cualquier lugar
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "n8n-automation-sg"
  }
}

# Crear la instancia EC2
resource "aws_instance" "n8n_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.n8n_key.key_name

  vpc_security_group_ids = [aws_security_group.n8n_sg.id]

  # Script de inicialización (opcional)
  user_data = <<-EOF
              #!/bin/bash
              # Actualizar el sistema
              yum update -y
              
              # Instalar Docker
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              
              # Instalar Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
              
              # Instalar Nginx
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              
              # Instalar Certbot (Let's Encrypt) desde EPEL
              yum install -y epel-release
              yum install -y certbot python3-certbot-nginx
              
              # Crear configuración básica de Nginx
              sudo cat > /etc/nginx/conf.d/n8nserver.conf << 'NGINXCONF'
              server {
                  listen 80;
                  server_name TU_DOMINIO_AQUI;
                  
                  location / {
                      proxy_pass http://localhost:5678;
                      proxy_set_header Connection '';
                      proxy_http_version 1.1;
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto $scheme;
                      proxy_buffering off;
                      proxy_buffer_size 16k;
                      proxy_busy_buffers_size 24k;
                      proxy_buffers 64 4k;
                      chunked_transfer_encoding off;
                  }
                  
                  # For websocket support (used by n8n editor)
                  location /socket.io/ {
                      proxy_pass http://localhost:5678/socket.io/;
                      proxy_set_header Host $host;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection "upgrade";
                  }
                  
                  # Let's Encrypt validation
                  location /.well-known/acme-challenge/ {
                      root /var/www/html;
                  }
              }
              NGINXCONF
              
              # Crear directorio web para Let's Encrypt
              mkdir -p /var/www/html
              
              # Reiniciar Nginx para aplicar configuración
              systemctl restart nginx
              
              # Obtener certificado SSL automáticamente
              certbot --nginx -d TU_DOMINIO_AQUI --non-interactive --agree-tos --email TU_MAIL_AQUI
              
              # Configurar renovación automática de certificados
              echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
              
              # Crear docker-compose.yml para n8n
              mkdir -p /opt/automation-server
              cat > /opt/automation-server/docker-compose.yml << 'DOCKERCOMPOSE'
              services:
                n8n:
                  image: n8nio/n8n:latest
                  restart: always
                  ports:
                    - "5678:5678"
                  environment:
                    - N8N_HOST=TU_DOMINIO_AQUI
                    - N8N_PROTOCOL=https
                    - N8N_PORT=5678
                    - N8N_WEBHOOK_URL= https://TU_DOMINIO_AQUI
                    - WEBHOOK_URL=https://TU_DOMINIO_AQUI
                    - NODE_ENV=production
                    - N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
                    - N8N_TRUSTED_PROXY_RANGES=0.0.0.0/0
                    - N8N_RUNNERS_ENABLED=true
                    - N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true
                    - NODE_TLS_REJECT_UNAUTHORIZED=1
                  volumes:
                    - n8n_data:/home/node/.n8n
              
              volumes:
                n8n_data:
              DOCKERCOMPOSE
              
              # Iniciar n8n automáticamente
              cd /opt/automation-server
              docker-compose up -d
              EOF

  tags = {
    Name = "n8n-automation-server"
  }
}

# Output para mostrar información importante
output "instance_public_ip" {
  description = "Dirección IP pública de la instancia"
  value       = aws_instance.n8n_server.public_ip
}

output "instance_public_dns" {
  description = "DNS público de la instancia"
  value       = aws_instance.n8n_server.public_dns
}

output "ssh_connection_command" {
  description = "Comando para conectarse via SSH"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.n8n_server.public_ip}"
}