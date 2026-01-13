// =============================================================================
// MeetingRecorder Content Script - Google Meet ページ内の監視
// =============================================================================
// このスクリプトはGoogle Meetのページ内で動作し、
// 会議の参加・退出を検知してbackground scriptに通知します。
// =============================================================================

let isInMeeting = false;
let checkInterval = null;

// 会議中かどうかを判定する
function checkMeetingState() {
  // 会議中に存在する要素を確認
  // - 退出ボタン（data-tooltip に「通話から退出」などが含まれる）
  // - 会議コントロールバー
  const leaveButton = document.querySelector('[data-tooltip*="退出"], [data-tooltip*="Leave"], [aria-label*="退出"], [aria-label*="Leave call"]');
  const controlBar = document.querySelector('[data-call-active="true"]');
  const meetingUI = document.querySelector('[data-meeting-title], [data-self-name]');

  // いずれかの要素が存在すれば会議中
  const nowInMeeting = !!(leaveButton || controlBar || meetingUI);

  // 状態が変化した場合のみ通知
  if (nowInMeeting !== isInMeeting) {
    isInMeeting = nowInMeeting;

    // background scriptに通知
    chrome.runtime.sendMessage({
      type: nowInMeeting ? 'meeting_joined' : 'meeting_left',
      title: document.title
    });

    console.log(`Meeting state changed: ${nowInMeeting ? 'joined' : 'left'}`);
  }
}

// 監視を開始
function startMonitoring() {
  // 初回チェック
  checkMeetingState();

  // 1秒ごとにチェック（DOMの変化を監視）
  checkInterval = setInterval(checkMeetingState, 1000);

  // MutationObserverでDOMの変化も監視
  const observer = new MutationObserver(() => {
    checkMeetingState();
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['data-call-active', 'data-meeting-title']
  });

  console.log('MeetingRecorder content script started');
}

// ページ読み込み完了後に監視開始
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', startMonitoring);
} else {
  startMonitoring();
}
