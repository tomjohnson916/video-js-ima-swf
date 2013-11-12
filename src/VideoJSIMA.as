package {

import flash.display.Sprite;
import flash.system.Security;
import flash.text.TextField;
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

[SWF(backgroundColor="#000000", frameRate="60", width="640", height="360")]
public class VideoJSIMA extends Sprite {

	private static const LINEAR_AD_TAG:String =
			"http://pubads.g.doubleclick.net/gampad/ads?sz=400x300&" +
					"iu=%2F6062%2Fiab_vast_samples&ciu_szs=300x250%2C728x90&impl=s&" +
					"gdfp_req=1&env=vp&output=xml_vast2&unviewed_position_start=1&" +
					"url=[referrer_url]&correlator=[timestamp]&" +
					"cust_params=iab_vast_samples%3Dlinear";

	private static const NONLINEAR_AD_TAG:String =
			"http://pubads.g.doubleclick.net/gampad/ads?sz=400x300&" +
					"iu=%2F6062%2Fiab_vast_samples&ciu_szs=300x250%2C728x90&" +
					"impl=s&gdfp_req=1&env=vp&output=xml_vast2&unviewed_position_start=1&" +
					"url=[referrer_url]&correlator=[timestamp]&" +
					"cust_params=iab_vast_samples%3Dimageoverlay";

	private var adsLoader:AdsLoader;
	private var adsManager:AdsManager;
	private var contentPlayheadTime:Number;

	public function VideoJSIMA() {
		// Allow JS calls from other domains
		Security.allowDomain("*");
		Security.allowInsecureDomain("*");

		// add content-menu version info
		var _ctxVersion:ContextMenuItem = new ContextMenuItem("VideoJS Flash IMA Component v0.0.11", false, false);
		var _ctxAbout:ContextMenuItem = new ContextMenuItem("Copyright © 2013 Brightcove, Inc.", false, false);
		var _ctxMenu:ContextMenu = new ContextMenu();
		_ctxMenu.hideBuiltInItems();
		_ctxMenu.customItems.push(_ctxVersion, _ctxAbout);
		this.contextMenu = _ctxMenu;
		trace('hello');

		requestAds(LINEAR_AD_TAG);
    }

	/**
	 * Instantiate the AdsLoader and load the SDK
	 */
	private function initAdsLoader():void {
		if (adsLoader == null) {
			// On the first request, create the AdsLoader.
			adsLoader = new AdsLoader();
			// The SDK uses a 2 stage loading process. Without this call, the second
			// loading stage will take place when ads are requested. Including this
			// call will decrease latency in starting ad playback.
			adsLoader.loadSdk();
			adsLoader.addEventListener(AdsManagerLoadedEvent.ADS_MANAGER_LOADED,
					adsManagerLoadedHandler);
			adsLoader.addEventListener(AdErrorEvent.AD_ERROR, adsLoadErrorHandler);
		}
	}

	/**
	 * Request ads using the specified ad tag.
	 *
	 * @param adTag A URL that will return a valid VAST response.
	 */
	private function requestAds(adTag:String):void {
		trace('request Ads');
		initAdsLoader();
		// The AdsRequest encapsulates all the properties required to request ads.
		var adsRequest:AdsRequest = new AdsRequest();
		adsRequest.adTagUrl = adTag;
		adsRequest.linearAdSlotWidth = 640;
		adsRequest.linearAdSlotHeight = 360;
		adsRequest.nonLinearAdSlotWidth = 640;
		adsRequest.nonLinearAdSlotHeight = 360;

		// Instruct the AdsLoader to request ads using the AdsRequest object.
		adsLoader.requestAds(adsRequest);
	}

	/**
	 * Invoked when the AdsLoader successfully fetched ads.
	 */
	private function adsManagerLoadedHandler(event:AdsManagerLoadedEvent):void {
		trace('loaded');
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
			adsManager.addEventListener(AdEvent.ALL_ADS_COMPLETED,
					allAdsCompletedHandler);
			// If ad is linear, it will fire content pause request event.
			adsManager.addEventListener(AdEvent.CONTENT_PAUSE_REQUESTED,
					contentPauseRequestedHandler);
			// When ad finishes or if ad is non-linear, content resume event will be
			// fired. For example, if VMAP response only has post-roll, content
			// resume will be fired for pre-roll ad (which is not present) to signal
			// that content should be started or resumed.
			adsManager.addEventListener(AdEvent.CONTENT_RESUME_REQUESTED,
					contentResumeRequestedHandler);
			// We want to know when an ad starts.
			adsManager.addEventListener(AdEvent.STARTED, startedHandler);
			adsManager.addEventListener(AdErrorEvent.AD_ERROR,
					adsManagerPlayErrorHandler);

			// If your video player supports a specific version of VPAID ads, pass
			// in the version. If your video player does not support VPAID ads yet,
			// just pass in 1.0.
			adsManager.handshakeVersion("1.0");
			// Init should be called before playing the content in order for VMAP
			// ads to function correctly.
			adsManager.init(640,360,ViewModes.NORMAL);

			// Add the adsContainer to the display list. Below is an example of how
			// to do it in Flex.
			addChild(adsManager.adsContainer);

			// Start the ad playback.
			adsManager.start();

			requestAds(LINEAR_AD_TAG);
		}
	}

	/**
	 * Clean up AdsManager references when no longer needed. Explicit cleanup
	 * is necessary to prevent memory leaks.
	 */
	private function destroyAdsManager():void {
		//enableContentControls();
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
	}

	/**
	 * The AdsManager raises this event when it requests the publisher to pause
	 * the content.
	 */
	private function contentPauseRequestedHandler(event:AdEvent):void {
		// The ad will cover a large portion of the content, therefore content
		// must be paused.
		//if (videoPlayer.playing) {
		//	videoPlayer.pause();
		//}
		// Rewire controls to affect ads manager instead of the content video.
		//enableLinearAdControls();
		// Ads usually do not allow scrubbing.
		//canScrub = false;
	}

	/**
	 * If an error occurs during the ads manager play, the content should be
	 * resumed. In this example, the content is resumed if there's an error
	 * playing ads.
	 */
	private function adsManagerPlayErrorHandler(event:AdErrorEvent):void {
		trace("warning", "Ad playback error: " + event.error.errorMessage);
		destroyAdsManager();
		//enableContentControls();
		//videoPlayer.play();
	}

	/**
	 * If an error occurs during the ads load, the content can be resumed or
	 * another ads request can be made. In this example, the content is resumed
	 * if there's an error loading ads.
	 */
	private function adsLoadErrorHandler(event:AdErrorEvent):void {
		trace("warning", "Ads load error: " + event.error.errorMessage);
		//videoPlayer.play();
	}

	/**
	 * The AdsManager raises this event when it requests the publisher to resume
	 * the content.
	 */
	private function contentResumeRequestedHandler(event:AdEvent):void {
		// Rewire controls to affect content instead of the ads manager.
		//enableContentControls();
		//videoPlayer.play();
	}

	/**
	 * The AdsManager raises this event when the ad has started.
	 */
	private function startedHandler(event:AdEvent):void {
		// If the ad exists and is a non-linear, start the content with the ad.
		if (event.ad != null && !event.ad.linear) {
			//videoPlayer.play();
		}
	}
}
}
