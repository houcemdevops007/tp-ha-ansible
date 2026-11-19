<%@ page contentType="text/html; charset=UTF-8" isErrorPage="true" %>
<%
    Object codeObjet = request.getAttribute("javax.servlet.error.status_code");
    String code = (codeObjet == null) ? "?" : codeObjet.toString();
%>
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Erreur <%= code %></title>
  <style>
    body { font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;
           background:#f4f6f8; color:#1f2933; margin:0;
           display:flex; align-items:center; justify-content:center;
           min-height:100vh; }
    .boite { background:#fff; border:1px solid #dbe2ea; border-radius:10px;
             padding:40px 48px; text-align:center; max-width:460px; }
    h1 { font-size:3rem; margin:0 0 8px; color:#b83280; }
    a { color:#2b6cb0; }
  </style>
</head>
<body>
  <div class="boite">
    <h1><%= code %></h1>
    <p>La ressource demandée est introuvable sur ce serveur d'application.</p>
    <p><a href="/app/">Retour à l'application</a></p>
  </div>
</body>
</html>
