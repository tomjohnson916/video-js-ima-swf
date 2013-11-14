package {

import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.system.Security;
import com.google.ads.ima.api.AdErrorEvent;
import com.google.ads.ima.api.AdEvent;
import com.google.ads.ima.api.AdsLoader;
import com.google.ads.ima.api.AdsManager;
import com.google.ads.ima.api.AdsManagerLoadedEvent;
import com.google.ads.ima.api.AdsRenderingSettings;
import com.google.ads.ima.api.AdsRequest;
import com.google.ads.ima.api.ViewModes;

import flash.ui.ContextMenu;
import flash.ui.ContextMenuItem;
import flash.utils.Timer;

[SWF(backgroundColor="#000000", frameRate="60", width="640", height="360")]
public class VideoJSIMA extends Sprite {

	private var adsLoader:AdsLoader;
	private var adsManager:AdsManager;
	private var contentPlayheadTime:Number = 0;
	private var _stageSizeTimer:Timer;
	private var _contentPlayerId:String;

	public function VideoJSIMA() {
		_stageSizeTimer = new Timer(250);
		_stageSizeTimer.addEventListener(TimerEvent.TIMER, onStageSizeTimerTick);
		addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
	}

	private function init():void {
		// Allow JS calls from other domains
		Security.allowDomain("*");
		Security.allowInsecureDomain("*");

		ExternalInterface.addCallback('trigger', onTrigger);

		// add content-menu version info
		var _ctxVersion:ContextMenuItem = new ContextMenuItem("VideoJS Flash IMA Component v0.0.2", false, false);
		var _ctxAbout:ContextMenuItem = new ContextMenuItem("Copyright © 2013 Brightcove, Inc.", false, false);
		var _ctxMenu:ContextMenu = new ContextMenu();
		_ctxMenu.hideBuiltInItems();
		_ctxMenu.customItems.push(_ctxVersion, _ctxAbout);
		this.contextMenu = _ctxMenu;

		if(loaderInfo.parameters.playerId)
		{
			_contentPlayerId = loaderInfo.parameters.playerId;

			console('registered a content player at ' + _contentPlayerId );
		}

		initAdsLoader();
	}

	/**
	 * Instantiate the AdsLoader and load the SDK
	 */
	private function initAdsLoader():void {
		console('init ads loader');
		if (adsLoader == null) {
			// On the first request, create the AdsLoader.
			adsLoader = new AdsLoader();
			// The SDK uses a 2 stage loading process. Without this call, the second
			// loading stage will take place when ads are requested. Including this
			// call will decrease latency in starting ad playback.
			adsLoader.loadSdk();
			adsLoader.addEventListener(AdsManagerLoadedEvent.ADS_MANAGER_LOADED, adsManagerLoadedHandler);
			adsLoader.addEventListener(AdErrorEvent.AD_ERROR, adsLoadErrorHandler);
		}
	}

	/**
	 * Request ads using the specified ad tag.
	 *
	 * @param adTag A URL that will return a valid VAST response.
	 */
	public function requestAds(adTag:String):void {
		console('request ads ' + adTag);
		if(!adsManager)	initAdsLoader();

		// The AdsRequest encapsulates all the properties required to request ads.
		var adsRequest:AdsRequest = new AdsRequest();
		adsRequest.adTagUrl = adTag;
		adsRequest.linearAdSlotWidth = stage.stageWidth;
		adsRequest.linearAdSlotHeight = stage.stageHeight;
		adsRequest.nonLinearAdSlotWidth = stage.stageWidth;
		adsRequest.nonLinearAdSlotHeight = stage.stageHeight;

		// Instruct the AdsLoader to request ads using the AdsRequest object.
		adsLoader.requestAds(adsRequest);
	}

	/**
	 * Invoked when the AdsLoader successfully fetched ads.
	 */
	private function adsManagerLoadedHandler(event:AdsManagerLoadedEvent):void {
		console('loaded ads manager');

		// Publishers can modify the default preferences through this object.
		var adsRenderingSettings:AdsRenderingSettings =
				new AdsRenderingSettings();

		// In order to support VMAP ads, ads manager requires an object that
		// provides current playhead position for the content.
		var contentPlayhead:Object = {};
		contentPlayhead.time = function():Number {
			return contentPlayheadTime * 1000; // convert to milliseconds.
		};

		// Get a reference to the AdsManager object through the event object.
		adsManager = event.getAdsManager(contentPlayhead, adsRenderingSettings);
		if (adsManager) {
			// Add required ads manager listeners.
			// ALL_ADS_COMPLETED event will fire once all the ads have played. There
			// might be more than one ad played in the case of ad pods and VMAP.
			adsManager.addEventListener(AdEvent.ALL_ADS_COMPLETED, allAdsCompletedHandler);
			// If ad is linear, it will fire content pause request event.
			adsManager.addEventListener(AdEvent.CONTENT_PAUSE_REQUESTED, contentPauseRequestedHandler);
			// When ad finishes or if ad is non-linear, content resume event will be
			// fired. For example, if VMAP response only has post-roll, content
			// resume will be fired for pre-roll ad (which is not present) to signal
			// that content should be started or resumed.
			adsManager.addEventListener(AdEvent.CONTENT_RESUME_REQUESTED, contentResumeRequestedHandler);
			// We want to know when an ad starts.
			adsManager.addEventListener(AdEvent.STARTED, startedHandler);
			adsManager.addEventListener(AdErrorEvent.AD_ERROR, adsManagerPlayErrorHandler);

			// If your video player supports a specific version of VPAID ads, pass
			// in the version. If your video player does not support VPAID ads yet,
			// just pass in 1.0.
			adsManager.handshakeVersion("1.0");
			// Init should be called before playing the content in order for VMAP
			// ads to function correctly.
			adsManager.init(stage.stageWidth,stage.stageHeight,ViewModes.NORMAL);

			// Add the adsContainer to the display list. Below is an example of how
			// to do it in Flex.
			addChild(adsManager.adsContainer);

			contentPlayerTrigger('adsready');
		}
	}

	/**
	 * Clean up AdsManager references when no longer needed. Explicit cleanup
	 * is necessary to prevent memory leaks.
	 */
	private function destroyAdsManager():void {
		if (adsManager) {
			if (adsManager.adsContainer.parent &&
					adsManager.adsContainer.parent.contains(adsManager.adsContainer)) {
				adsManager.adsContainer.parent.removeChild(adsManager.adsContainer);
			}
			adsManager.destroy();
		}
	}

	/**
	 * The AdsManager raises this event when all ads for the request have been
	 * played.
	 */
	private function allAdsCompletedHandler(event:AdEvent):void {
		// Ads manager can be destroyed after all of its ads have played.
		destroyAdsManager();
		console('All ads have completed');
	}

	/**
	 * The AdsManager raises this event when it requests the publisher to pause
	 * the content.
	 */
	private function contentPauseRequestedHandler(event:AdEvent):void {
		console('content pause request');
		//Todo if i have an ad, and it is linear, and it is preroll, play it

		if(_contentPlayerId)
		{
			console('sending back startlinearadmode');
			ExternalInterface.call('window.videojs.players['+_contentPlayerId+'].ads.startLinearAdMode');
		}

	}

	/**
	 * If an error occurs during the ads manager play, the content should be
	 * resumed. In this example, the content is resumed if there's an error
	 * playing ads.
	 */
	private function adsManagerPlayErrorHandler(event:AdErrorEvent):void {
		console("Ad playback error: " + event.error.errorMessage);
		destroyAdsManager();
	}

	/**
	 * If an error occurs during the ads load, the content can be resumed or
	 * another ads request can be made. In this example, the content is resumed
	 * if there's an error loading ads.
	 */
	private function adsLoadErrorHandler(event:AdErrorEvent):void {
		console("Ads load error: " + event.error.errorMessage);
	}

	/**
	 * The AdsManager raises this event when it requests the publisher to resume
	 * the content.
	 */
	private function contentResumeRequestedHandler(event:AdEvent):void {
		console('content resume request');
		if(_contentPlayerId)
		{
			console('sending back endlinearadmode');
			ExternalInterface.call('window.videojs.players['+_contentPlayerId+'].ads.endLinearAdMode');
		}
	}

	/**
	 * The AdsManager raises this event when the ad has started.
	 */
	private function startedHandler(event:AdEvent):void {
		console('An ad has started');
	}

	private function onContentUpdate(value:*):void {
		console('External call for onContentUpdate received');
		requestAds(value.serverUrl);
	}

	private function onPrerollReady(value:*):void {
		console('External call for onPrerollReady received');

		// Start the ad playback.
		adsManager.start();
	}

	private function onContentComplete(value:*):void {
		console('External call for onContentComplete received');
	}

	/**
	 * Notify the player of an ad integration event.
	 */
	private function contentPlayerTrigger(event:String):void
	{
		if(_contentPlayerId)
		{
			var commandString:String = 'window.videojs.players['+_contentPlayerId+'].trigger';
			try{
				ExternalInterface.call(commandString, event);
			} catch(err:Error) {
				console('There was an error notifying player of ' +  event);
			}
		} else {
			console('trigger called, but no player registered');
		}
	}

	private function console(value:*):void {
		try{
			ExternalInterface.call('window.console.log', "["+ExternalInterface.objectID+"]", value);
		} catch(err:Error) {

		}
	}

	private function onStageSizeTimerTick(e:TimerEvent):void{
		if(stage.stageWidth > 0 && stage.stageHeight > 0){
			_stageSizeTimer.stop();
			_stageSizeTimer.removeEventListener(TimerEvent.TIMER, onStageSizeTimerTick);
			init();
		}
	}

	private function onStageResize(e:Event):void{
		console('stage resize');
	}

	private function onAddedToStage(e:Event):void{
		stage.addEventListener(MouseEvent.CLICK, onStageClick);
		stage.addEventListener(Event.RESIZE, onStageResize);
		stage.scaleMode = StageScaleMode.NO_SCALE;
		stage.align = StageAlign.TOP_LEFT;
		_stageSizeTimer.start();
	}

	private function onStageClick(e:MouseEvent):void{
		console('IMA SWF just stole your click');
	}

	private function onTrigger(e:*):void{
		// then what?
		if(e.type)
		{
			switch(e.type)
			{
				case 'contentupdate':
					onContentUpdate(e.options);
					break;

				case 'readyforpreroll':
					onPrerollReady(e.options);
					break;

				case 'ended':
					onContentComplete(e.options);
					break;

				default:
					break;
			}
		}


	}
}
}
