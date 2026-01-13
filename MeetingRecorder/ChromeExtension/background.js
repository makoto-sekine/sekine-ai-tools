// =============================================================================
// MeetingRecorder Chrome Extension - Background Service Worker
// =============================================================================
// Content Scriptからの会議参加・退出通知を受け取り、
// MeetingRecorderアプリに通知します。
// =============================================================================

const APP_SERVER_URL = 'http://localhost:52828';

// 現在の会議状態を追跡
let currentMeeting = {
  isInMeeting: false,
  meetingTitle: null,
  tabId: null
};

// =============================================================================
// Content Scriptからのメッセージを受信
// =============================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Received message:', message, 'from tab:', sender.tab?.id);

  if (message.type === 'meeting_joined') {
    handleMeetingJoined(sender.tab, message.title);
  } else if (message.type === 'meeting_left') {
    handleMeetingLeft(sender.tab);
  }

  sendResponse({ received: true });
  return true;
});

// =============================================================================
// 会議イベントの処理
// =============================================================================

function handleMeetingJoined(tab, title) {
  // 既に会議中の場合は無視
  if (currentMeeting.isInMeeting) {
    // ただしタイトルが更新された場合は通知
    const meetingTitle = extractMeetingTitle(title);
    if (meetingTitle !== currentMeeting.meetingTitle && meetingTitle !== 'GoogleMeet') {
      console.log(`Title updated: ${currentMeeting.meetingTitle} -> ${meetingTitle}`);
      currentMeeting.meetingTitle = meetingTitle;
      notifyApp('meeting_title_updated', { meetingTitle: meetingTitle });
    }
    return;
  }

  const meetingTitle = extractMeetingTitle(title);
  console.log(`Meeting joined: ${meetingTitle}`);

  currentMeeting = {
    isInMeeting: true,
    meetingTitle: meetingTitle,
    tabId: tab?.id
  };

  // アプリに通知
  notifyApp('meeting_start', { meetingTitle: meetingTitle });
}

function handleMeetingLeft(tab) {
  // 会議中でない場合は無視
  if (!currentMeeting.isInMeeting) return;

  // 別のタブからの通知は無視
  if (tab?.id && currentMeeting.tabId && tab.id !== currentMeeting.tabId) return;

  console.log(`Meeting left: ${currentMeeting.meetingTitle}`);

  // アプリに通知
  notifyApp('meeting_end', { meetingTitle: currentMeeting.meetingTitle });

  currentMeeting = {
    isInMeeting: false,
    meetingTitle: null,
    tabId: null
  };
}

// =============================================================================
// タイトル抽出
// =============================================================================

function extractMeetingTitle(title) {
  if (!title) return 'GoogleMeet';

  // "会議タイトル - Google Meet" からタイトルを抽出
  const match = title.match(/^(.+?)\s*-\s*Google Meet$/);
  if (match) {
    return sanitizeTitle(match[1]);
  }

  // "Meet - 会議タイトル" からタイトルを抽出
  const meetMatch = title.match(/^Meet\s*-\s*(.+)$/);
  if (meetMatch) {
    return sanitizeTitle(meetMatch[1]);
  }

  return 'GoogleMeet';
}

function sanitizeTitle(title) {
  return title
    .replace(/[\/\\:*?"<>|]/g, '_')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
    .substring(0, 50) || 'GoogleMeet';
}

// =============================================================================
// アプリへの通知
// =============================================================================

async function notifyApp(event, data) {
  try {
    const response = await fetch(`${APP_SERVER_URL}/meeting-event`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        event: event,
        ...data,
        timestamp: new Date().toISOString()
      })
    });

    if (!response.ok) {
      console.error(`App notification failed: ${response.status}`);
    } else {
      console.log(`App notified: ${event}`, data);
    }
  } catch (error) {
    console.log(`App not running: ${error.message}`);
  }
}

// =============================================================================
// タブ監視（タブが閉じられた場合の検知）
// =============================================================================

chrome.tabs.onRemoved.addListener((tabId) => {
  if (currentMeeting.tabId === tabId && currentMeeting.isInMeeting) {
    console.log('Meeting tab closed');
    handleMeetingLeft({ id: tabId });
  }
});

console.log('MeetingRecorder extension loaded (Content Script mode)');
