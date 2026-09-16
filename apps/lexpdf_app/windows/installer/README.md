# LexPDF para Windows

A distribuição Windows possui um instalador por usuário (`LexPDF-Setup.exe`).

O instalador:

- instala o LexPDF em `%LOCALAPPDATA%\\Programs\\LexPDF`, sem exigir administrador;
- cria atalho no Menu Iniciar e oferece atalho opcional na Área de Trabalho;
- registra `LexPDF.PDF` e as capacidades do aplicativo para que o Windows mostre o LexPDF em **Abrir com** para `.pdf`, sem adulterar o `UserChoice` protegido do Windows 10/11;
- mantém uma única instância do aplicativo: novos PDFs abertos pelo Explorer são encaminhados para a janela existente;
- aceita arrastar PDFs ou pastas do Explorer para a janela; pastas são pesquisadas recursivamente até o limite de 10 abas.

O instalador é compilado e instalado de forma silenciosa no CI para validar o executável e o registro do manipulador de PDF antes de publicar o artefato.
