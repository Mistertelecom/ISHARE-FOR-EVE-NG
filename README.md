# ISHARE-FOR-EVE-NG

**ISHARE-FOR-EVE-NG** é um script de automação projetado para facilitar a integração de imagens do sistema **IShare2** diretamente no ambiente de laboratório **EVE-NG**.

Este projeto automatiza o processo de download, instalação e configuração de imagens (QEMU/KVM), ajustando permissões e nomes de arquivos conforme necessário para o perfeito funcionamento no EVE-NG.

## 🚀 Funcionalidades

- **Instalação Automática do IShare2**: Verifica e instala o cliente `ishare2` se não estiver presente.
- **Adapter Dedicado (ishare2-eve)**: Cria um adaptador inteligente entre o IShare2 e o EVE-NG.
- **Correção de Imagens**: Normaliza automaticamente nomes de arquivos de disco para `virtioa.qcow2` (padrão EVE-NG).
- **Fix Permissions**: Executa automaticamente o script de correção de permissões do EVE-NG (`unl_wrapper -a fixpermissions`).
- **Detecção Inteligente**:
  - Identifica se está rodando em EVE-NG ou PNETLab (foco em EVE-NG).
  - Localiza automaticamente o diretório de armazenamento (Store) do IShare2.
- **Segurança**: Valida integridade e tamanho mínimo das imagens antes da instalação.

## 📋 Pré-requisitos

- Sistema Operacional: **Ubuntu/Debian** (Base do EVE-NG).
- Acesso **Root** (sudo).
- Conexão com a Internet.

## 📦 Instalação

1. Clone este repositório ou baixe o script `ISHARE2_EVE_NG.SH`.
2. Dê permissão de execução:
   ```bash
   chmod +x ISHARE2_EVE_NG.SH
   ```
3. Execute como root:
   ```bash
   sudo ./ISHARE2_EVE_NG.SH
   ```

O script irá configurar todo o ambiente e instalar o comando `ishare2-eve` no seu sistema.

## 🛠️ Como Usar

Após a instalação, utilize o comando `ishare2-eve` para gerenciar suas imagens.

### Comandos Principais

- **Baixar e Instalar uma Imagem (Recomendado)**:
  Baixa a imagem do repositório ishare2 e a instala imediatamente no EVE-NG.
  ```bash
  ishare2-eve pull-install qemu <nome-da-imagem>
  ```
  *Exemplo:* `ishare2-eve pull-install qemu mikrotik-7.17`

- **Apenas Baixar (Pull)**:
  Apenas baixa a imagem para o cache local do ishare2.
  ```bash
  ishare2-eve pull qemu <nome-da-imagem>
  ```

- **Instalar Imagem Já Baixada**:
  Instala uma imagem que já está no cache local do ishare2 para o EVE-NG.
  ```bash
  ishare2-eve install qemu <nome-da-imagem>
  ```

### Exemplos de Uso

1. **Pesquisar uma imagem**:
   ```bash
   ishare2 search qemu cisco
   ```

2. **Instalar um roteador Cisco**:
   ```bash
   ishare2-eve pull-install qemu cisco-iou-l2
   ```

## 👤 Autor

**João Pedro**

---
*Este projeto é uma contribuição para a comunidade EVE-NG, visando simplificar a gestão de imagens de laboratório.*
