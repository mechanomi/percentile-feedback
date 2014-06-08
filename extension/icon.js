function unixtime() {
  return Math.floor(Date.now() / 1000);
}

function loadJS(page, name, interaction) {
  var req = new XMLHttpRequest();
  var data = page.replace(/([^\/]+)?$/, "") + name;
  req.open("GET", data + "?" + unixtime(), false);
  try { req.send(null); }
  catch (exception) {
    req.status === null;
  }

  if (req.status === 200) {
    console.log("Reloading " + name);
    eval.call(window, req.responseText);
  } else {
    if (interaction) {
      alert("You need to set a page in extension options!");
      return;
    }
  }
}

function updateIcon(interaction) {
  var icon = document.createElement("canvas");
  icon.setAttribute("height", "19");
  icon.setAttribute("width", "19");
  context = icon.getContext("2d");
  var page = localStorage["page"] || ".";

  loadJS(page, "jquery.min.js", interaction);
  loadJS(page, "pouchdb.min.js", interaction);
  loadJS(page, "d3.min.js", interaction);

  var req1 = new XMLHttpRequest();
  var data = page.replace(/([^\/]+)?$/, "") + "chart.js";
  req1.open("GET", data + "?" + unixtime(), false);
  try { req1.send(null); }
  catch (exception) {
    req1.status === null;
  }

  if (req1.status === 200) {
    console.log("Reloading chart.js");
    eval.call(window, req1.responseText);
  } else {
    if (interaction) {
      alert("You need to set a page in extension options!");
      return;
    }

    context.textAlign = "center";
    context.font = "9px Verdana";
    context.fillText("PR", 9.5, 9);
    context.fillText("?", 9.5, 17);

    var imageData = context.getImageData(0, 0, 19, 19);
    chrome.browserAction.setIcon({imageData: imageData});
    return;
  }

  pf.action = function(views, data) {
    if (data.pr < 50) {
      context.fillStyle = "#c00";
      context.fillRect(0, 0, 19, 19);
      context.fillStyle = "#fee";
    } else {
      context.fillStyle = "#090";
    }
    context.textAlign = "center";
    context.font = "9px Verdana";
    context.fillText("PR", 9.5, 9);
    context.fillText(data.pr.toFixed(0), 9.5, 17);

    var imageData = context.getImageData(0, 0, 19, 19);
    chrome.browserAction.setIcon({imageData: imageData});
  }
  pf.compute();
  return true;
}

function openPage() {
  var page = localStorage["page"];
  var opened = updateIcon(true);

  chrome.tabs.query({url: page}, function (tabs) {
    if (tabs.length > 0) {
      chrome.tabs.update(tabs[0].id, {selected: true});
      chrome.tabs.reload(tabs[0].id);
    } else if (opened) {
      chrome.tabs.create({url: page}, function (tab) {
        chrome.tabs.reload(tab.id);
      });
    }
  });
}

chrome.browserAction.onClicked.addListener(openPage);

// Could probably do a fancy thing to poll every few seconds
function updateIconLoop() {
  var refreshSeconds = localStorage["timeout"] || 60;
  if (!(unixtime() % refreshSeconds)) {
    console.log("Updating in loop! " + unixtime() + " " + refreshSeconds);
    updateIcon();
  }
  setTimeout(updateIconLoop, 1000);
}

updateIcon();
setTimeout(updateIconLoop, 5000);
