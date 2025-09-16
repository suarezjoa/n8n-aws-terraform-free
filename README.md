# 🚀 N8N Automation Server - Despliegue con Terraform

Despliega una instancia EC2 completa con N8N, SSL automático y Nginx en **solo 4 pasos**.

## 📋 Requisitos Previos

- **AWS CLI** configurado con credenciales
- **Terraform** instalado (versión ≥ 1.0)
- **Par de claves SSH** (se generará automáticamente si no existe)
- **Dominio DNS** tenes un dominio o subdominio y apuntarlo a nuestra IP publica de la instancia EC2 una vez creada (moficiar el archivo main.tf en los apartados       "TU_DOMINIO_AQUI" y "TU_MAIL_AQUI")

Si no tienes una Dominio puedes obtener uno gratis usando https://my.noip.com/

---

## 🎯 Paso 1: Preparar Credenciales AWS

```bash
# Configurar AWS CLI (si no está configurado)
aws configure

# Verificar configuración
aws sts get-caller-identity
```

**Resultado esperado:**
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012", 
    "Arn": "arn:aws:iam::123456789012:user/tu-usuario"
}
```

---

## 🔑 Paso 2: Generar Claves SSH

```bash
# Generar par de claves SSH (si no existen)
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa

# Verificar que se crearon
ls -la ~/.ssh/id_rsa*
```

**Archivos esperados:**
- `~/.ssh/id_rsa` (clave privada)
- `~/.ssh/id_rsa.pub` (clave pública)

---

## 🏗️ Paso 3: Desplegar Infraestructura

```bash
# Clonar/descargar el archivo main.tf
# Ajustar configuración si es necesario (región, dominio)

# Inicializar Terraform
terraform init

# Ver plan de ejecución
terraform plan

# Aplicar configuración
terraform apply
```

**Durante `terraform apply`:**
- Escribe `yes` cuando se solicite confirmación
- El proceso toma aproximadamente **3-5 minutos**
- Se crean automáticamente: EC2, Security Group, Key Pair

**Salida esperada:**
```bash
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

instance_public_ip = "54.123.45.67"
instance_public_dns = "ec2-54-123-45-67.compute-1.amazonaws.com"
ssh_connection_command = "ssh -i ~/.ssh/id_rsa ec2-user@54.123.45.67"
```

---

## 🌐 Paso 4: Configurar que tu DNS apunte a la IP publica de la instancia EC2 creada

### Mientas se esta realizando las instalacion tendras que ir a tu servicio de DNS y apuntar la DNS a la nueva IP publica creada por la instancia EC2.

### Luego de eso tendras que concetarte via SSH a tu instancia y actualizar el certificado

```bash
ssh_connection_command = "ssh -i ~/.ssh/id_rsa ec2-user@ TU IP"
certbot --nginx -d TU DNS  --non-interactive --agree-tos --email TU mail
```
### Luego de esto tendras que iniciar nuevamente el servicio de N8N con docker

```bash
cd /opt/automation-server
docker-compose up -d

### verificacion con
docker ps
```



## ✅ Verificación de Servicios

### Verificar estado desde SSH:
```bash
# Conectar via SSH
ssh -i ~/.ssh/id_rsa ec2-user@<TU-IP-PUBLICA>

# Verificar servicios
sudo systemctl status nginx
sudo systemctl status docker
docker ps

# Verificar certificados SSL
sudo ls -la /etc/letsencrypt/live/mcpservern8n.ddns.net/
```

## 🛠️ Configuración Incluida

| Servicio | Descripción | Puerto |
|----------|-------------|--------|
| **N8N** | Plataforma de automatización | 5678 |
| **Nginx** | Proxy reverso con SSL | 80, 443 |
| **Docker** | Contenedores | - |
| **Let's Encrypt** | Certificados SSL gratuitos | - |

### Características de Seguridad:
- ✅ SSL/TLS automático
- ✅ Renovación automática de certificados
- ✅ Autenticación básica habilitada
- ✅ Firewall configurado (puertos 22, 80, 443)

### Optimización de Costos:
- ✅ Instancia `t2.micro` (Free Tier eligible)
- ✅ Almacenamiento `gp3` optimizado
- ✅ Amazon Linux 2023 (gratuito)
- ✅ Sin monitoring detallado

---

## 🔧 Comandos Útiles

### Gestión de N8N:
```bash
cd /opt/automation-server

# Reiniciar N8N
docker-compose restart

# Ver logs en tiempo real
docker logs n8n -f

# Parar servicios
docker-compose down

# Iniciar servicios
docker-compose up -d
```

### Gestión de SSL:
```bash
# Renovar certificado manualmente
sudo certbot renew

# Verificar expiración
sudo certbot certificates

# Reconfigurar SSL para nuevo dominio
sudo /opt/automation-server/setup-ssl.sh nuevo-dominio.com

---

## 🚨 Solución de Problemas

### SSL no funciona:
```bash
# Verificar certificados
sudo ls /etc/letsencrypt/live/mcpservern8n.ddns.net/

# Reconfigurar nginx sin SSL primero
sudo nano /etc/nginx/conf.d/automation.conf
sudo systemctl restart nginx

# Obtener certificados manualmente
sudo certbot --nginx -d mcpservern8n.ddns.net
```

### N8N no responde:
```bash
# Verificar que esté corriendo
docker ps | grep n8n

# Revisar logs
docker logs n8n

# Reiniciar contenedor
cd /opt/automation-server
docker-compose restart
```

### No puedo conectar por SSH:
```bash
# Verificar Security Group en AWS Console
# Asegurar que puerto 22 esté abierto

# Verificar clave SSH
ssh -i ~/.ssh/id_rsa -v ec2-user@<IP>
```

---

## 🗑️ Limpieza (Eliminar Recursos)

```bash
# Eliminar todos los recursos creados
terraform destroy

# Confirmar con 'yes'
# Se eliminan: EC2, Security Group, Key Pair
```

⚠️ **Advertencia:** Esto eliminará permanentemente la instancia y todos los datos.

---

## 📚 Referencias

- [Documentación N8N](https://docs.n8n.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [Let's Encrypt](https://letsencrypt.org/)
- [AWS Free Tier](https://aws.amazon.com/free/)
- [Medium](https://medium.com/@mmartinmainan/running-n8n-for-free-on-aws-a-self-hosting-guide-for-n8n-lovers-4e367727f45e)

**¡Listo!** Tu servidor N8N con SSL automático está funcionando 🎉