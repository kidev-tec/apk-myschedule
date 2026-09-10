import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Termos de Uso e Política de Privacidade (LGPD — Lei 13.709/2018).
///
/// Renderiza markdown estático embutido (sem rede). [isPrivacy] alterna
/// entre os dois documentos.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key, required this.isPrivacy});

  final bool isPrivacy;

  static const _terms = '''
**Termos de Uso — Minha Agenda**

*Última atualização: 09/09/2026*

## 1. O que é o app

O Minha Agenda é uma ferramenta para profissionais autônomos
(cabeleireiros, barbeiros, dentistas, veterinários e outros) gerenciarem
sua agenda de atendimentos e receberem agendamentos de clientes por um
link público.

## 2. Aceite

Ao criar uma conta você concorda com estes termos. Se não concorda,
não utilize o aplicativo.

## 3. Sua conta

- Você é responsável pelas informações do seu perfil e pelos dados dos
  seus clientes que cadastrar.
- A conta é **pessoal e intransferível**.
- O segmento de atuação é definido no cadastro inicial e fica vinculado
  à conta.

## 4. Agendamentos

- Agendamentos criados por clientes através do seu link público entram
  como **pendentes** e você confirma ou recusa.
- Cancelamentos de última hora são de responsabilidade mútua entre você
  e o cliente; o app apenas registra e facilita a comunicação.

## 5. Uso aceitável

É proibido usar o app para atividades ilegais, cadastrar dados de
terceiros sem autorização deles, ou tentar acessar dados de outros
usuários.

## 6. Disponibilidade

Buscamos 99% de disponibilidade, mas o serviço pode passar por
manutenções. Não garantimos que o serviço seja ininterrupto.

## 7. Assinatura e cancelamento

O app oferece período de teste gratuito. Após o período, é necessária
uma assinatura ativa para continuar criando e editando agendamentos.
Você pode cancelar quando quiser — os dados permanecem legíveis
(somente leitura).

## 8. Alterações destes termos

Podemos atualizar estes termos. Mudanças relevantes serão comunicadas
no app. O uso contínuo após a mudança implica aceite.

## 9. Contato

Dúvidas sobre estes termos: fale com o suporte pelo WhatsApp do
profissional responsável pela sua instalação.
''';

  static const _privacy = '''
**Política de Privacidade — Minha Agenda**

*Última atualização: 09/09/2026*

Esta política explica quais dados o Minha Agenda coleta, por que, e
quais são os seus direitos pela **LGPD (Lei 13.709/2018)**.

## 1. Dados que coletamos

**Sobre o profissional (você):**
- Nome, e-mail e telefone (cadastro/login via Google)
- Nome do negócio e segmento de atuação
- Horários de trabalho configurados

**Sobre os clientes que você cadastra:**
- Nome e WhatsApp (obrigatórios para o agendamento)
- E-mail e aniversário (opcionais)

**Sobre os agendamentos:**
- Serviço, data, hora, status e origem (app ou link público)

## 2. Por que coletamos (bases legais)

- **Execução de contrato**: os dados são necessários para o
  funcionamento da agenda que você contratou.
- **Legítimo interesse**: melhorias de segurança e prevenção a abusos.

Não usamos seus dados nem os dados dos seus clientes para publicidade.

## 3. Compartilhamento

Seus dados **não são vendidos nem compartilhados** com terceiros, exceto:
- Firebase/Google Cloud (infraestrutura: autenticação e banco de dados,
  protegidos por contrato de processamento de dados do Google);
- quando exigido por lei ou ordem judicial.

## 4. Onde os dados ficam

Em servidores do Google Cloud (Supabase), na região definida pelo
provedor, com criptografia em trânsito e em repouso.

## 5. Seus direitos (Art. 18 da LGPD)

A qualquer momento você pode solicitar:
- **Acesso** aos seus dados;
- **Correção** de dados incompletos ou desatualizados;
- **Portabilidade** (exportação);
- **Eliminação** dos dados — ao excluir sua conta, removemos
  permanentemente seus clientes e agendamentos (dados pessoais);
- **Informação** sobre com quem compartilhamos.

Para exercer qualquer direito, use a opção de exclusão de conta ou
fale com o suporte.

## 6. Dados dos SEUS clientes

Você é o **controlador** dos dados dos seus clientes — nós somos apenas
operadores. Se um seu cliente pedir os próprios dados ou a exclusão
deles, o pedido é com você, e o app te dá as ferramentas para atender
(excluir cliente apaga o registro do banco).

## 7. Retenção

Enquanto sua conta existir, os dados são mantidos. Após solicitação de
exclusão, os dados pessoais são removidos em até 30 dias, exceto
registros que a lei exija manter.

## 8. Menores de idade

O app não é direcionado a menores de 16 anos sem consentimento dos
responsáveis.

## 9. Contato

Encarregado (DPO): suporte da Minha Agenda via WhatsApp.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isPrivacy ? 'Política de Privacidade' : 'Termos de Uso'),
      ),
      // SafeArea + padding inferior: o fim do documento NUNCA fica atrás
      // da barra de gestos (home/voltar) — nada escondido na rolagem.
      body: SafeArea(
        child: Markdown(
          data: isPrivacy ? _privacy : _terms,
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            h2: Theme.of(context).textTheme.titleLarge,
            p: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
