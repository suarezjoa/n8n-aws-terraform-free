# Configurar el Proveedor de AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

# Configurar Proveedor AWS
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Nombre para el par de llaves SSH"
  type        = string
  default     = "n8n-server-key"
}

variable "instance_name" {
  description = "Nombre para la instancia EC2"
  type        = string
  default     = "n8n-automation-server"
}

# Fuente de datos para obtener la AMI más reciente de Amazon Linux 2023
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

# Obtener VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Obtener subredes por defecto en la primera zona de disponibilidad
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Crear un nuevo par de llaves
resource "tls_private_key" "n8n_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "n8n_key_pair" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.n8n_key.public_key_openssh

  tags = {
    Name = "n8n-server-keypair"
  }
}

# Guardar llave privada en archivo local
resource "local_file" "private_key" {
  content  = tls_private_key.n8n_key.private_key_pem
  filename = "${var.key_pair_name}.pem"
  file_permission = "0400"
}

# Grupo de Seguridad para el servidor n8n
resource "aws_security_group" "n8n_sg" {
  name_prefix = "n8n-server-sg"
  description = "Grupo de seguridad para el servidor de automatizacion n8n"
  vpc_id      = data.aws_vpc.default.id

  # Acceso SSH
  ingress {
    description = "Acceso SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Acceso HTTP
  ingress {
    description = "Acceso HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Acceso HTTPS
  ingress {
    description = "Acceso HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Puerto n8n (para acceso directo si es necesario)
  ingress {
    description = "Acceso directo a n8n"
    from_port   = 5678
    to_port     = 5678
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "n8n-server-security-group"
  }
}

# Instancia EC2
resource "aws_instance" "n8n_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.n8n_key_pair.key_name

  vpc_security_group_ids = [aws_security_group.n8n_sg.id]
  subnet_id              = data.aws_subnets.default.ids[0]
  
  # Asegurar asignación de IP pública
  associate_public_ip_address = true

  # Habilitar monitoreo detallado (opcional, gratuito para t2.micro)
  monitoring = true

  # Opciones de metadatos de instancia (buena práctica de seguridad)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }

  # Configuración del volumen raíz
  root_block_device {
    volume_type = "gp3"
    volume_size = 8  # 8 GB (elegible para capa gratuita)
    encrypted   = true
    delete_on_termination = true
  }

  # Script de configuración inicial para la instancia
  user_data = base64encode(<<-EOF
              #!/bin/bash
              # Actualizar el sistema
              yum update -y
              
              # Instalar y configurar SSM Agent (ya viene en Amazon Linux 2023 pero aseguramos que esté actualizado)
              yum install -y amazon-ssm-agent
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              
              # Instalar paquetes necesarios
              yum install -y docker git nginx python3-pip
              
              # Instalar Certbot
              pip3 install certbot certbot-nginx
              
              # Configurar Docker
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              
              # Instalar Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
              
              # Configurar Nginx
              systemctl start nginx
              systemctl enable nginx
            
              EOF
  )

  tags = {
    Name = var.instance_name
    Environment = "production"
    Application = "n8n"
    Description = "n8n automation server with Docker and Nginx"
  }
}

# Salidas (Outputs)
output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.n8n_server.id
}

output "instance_public_ip" {
  description = "Dirección IP pública de la instancia EC2"
  value       = aws_instance.n8n_server.public_ip
}

output "instance_public_dns" {
  description = "Nombre DNS público de la instancia EC2"
  value       = aws_instance.n8n_server.public_dns
}

output "ssh_connection_command" {
  description = "Comando SSH para conectarse a la instancia"
  value       = "ssh -i ${var.key_pair_name}.pem ec2-user@${aws_instance.n8n_server.public_ip}"
}

output "security_group_id" {
  description = "ID del grupo de seguridad"
  value       = aws_security_group.n8n_sg.id
}

output "private_key_filename" {
  description = "Nombre del archivo de la llave privada"
  value       = "${var.key_pair_name}.pem"
  sensitive   = true
}