<%@ page contentType="text/plain; charset=UTF-8" session="false" %><%--
  Page interrogée par le health check HAProxy :
      option httpchk GET /app/health.jsp

  session="false" est ESSENTIEL : sans cet attribut, Tomcat créerait une
  session HTTP à chaque appel du health check, soit 30 sessions par minute
  et par serveur, qui resteraient en mémoire pendant 30 minutes.
  C'est une fuite mémoire classique en production.

  Aucun saut de ligne entre la directive page et le corps : la réponse
  doit être exactement « OK ».
--%><%
    response.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
    response.setStatus(200);
%>OK
