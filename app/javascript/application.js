// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import 'darkModeManager';
import "@hotwired/turbo-rails";
import "controllers"; //pin of all from app/javascript/controllers
import "channels" //pin of all from app/javascript/channels

//shoelace
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path';
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.17.1/dist/');
import "@shoelace-style/shoelace/icon";
import "@shoelace-style/shoelace/icon-button";
import "@shoelace-style/shoelace/button";
import "@shoelace-style/shoelace/spinner";
import "@shoelace-style/shoelace/progress-bar";
import "@shoelace-style/shoelace/tab-group";
import "@shoelace-style/shoelace/tab";
import "@shoelace-style/shoelace/tab-panel";
//import "@shoelace-style/shoelace/dropdown";
//import "@shoelace-style/shoelace/input";
//import "@shoelace-style/shoelace/checkbox";
//import "@shoelace-style/shoelace/dialog";
//import "@shoelace-style/shoelace/textarea";


//add turbo:after-stream-render event to trigger after render
//const afterRenderEvent = new Event("turbo:after-stream-render");
//addEventListener("turbo:before-stream-render", (event) => {
//  const originalRender = event.detail.render
//  event.detail.render = function (streamElement) {
//    originalRender(streamElement)
//    document.dispatchEvent(afterRenderEvent);
//  }
//})