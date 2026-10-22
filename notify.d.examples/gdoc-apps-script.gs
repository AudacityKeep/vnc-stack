// Bound to a Google Doc: open the Doc, Extensions > Apps Script, paste this, set the token,
// then Deploy > New deployment > Web app (Execute as: Me, Who has access: Anyone).
// Use the deployment URL and the same token in gdoc.sh.
function doGet(e) {
  var secret = "PUT_A_LONG_RANDOM_TOKEN_HERE";
  if (e.parameter.token !== secret) {
    return ContentService.createTextOutput("Unauthorized");
  }

  var newUrl = e.parameter.vncurl;
  var body = DocumentApp.getActiveDocument().getBody();
  body.clear();
  var p = body.appendParagraph("");
  if (newUrl) {
    p.appendText("Open the menu").setLinkUrl(newUrl);
  } else {
    p.appendText("(No link this run, check the PC)");
  }
  body.appendParagraph("Last updated: " + new Date());

  return ContentService.createTextOutput("Updated");
}
