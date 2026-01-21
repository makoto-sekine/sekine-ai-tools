// =============================================================================
// MeetingRecorder Chrome Extension - Background Service Worker
// =============================================================================
// Content Scriptからの会議参加・退出通知を受け取り、
// MeetingRecorderアプリに通知します。
//
// 【状態管理】
// このスクリプトは常駐しているため、会議状態の真実（source of truth）として機能します。
// Content scriptがリロードされた場合、このスクリプトから状態を復元します。
// =============================================================================

const APP_SERVER_URL = 'http://localhost:52828';

// 現在の会議状態を追跡
let currentMeeting = {
  isInMeeting: false,
  meetingTitle: null,
  tabId: null,
  lastNotificationTime: null
};

// =============================================================================
// Content Scriptからのメッセージを受信
// =============================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[Background] Received message:', message.type, 'from tab:', sender.tab?.id);

  if (message.type === 'get_meeting_state') {
    // 状態取得リクエスト（content script起動時）
    sendResponse({
      isInMeeting: currentMeeting.isInMeeting,
      meetingTitle: currentMeeting.meetingTitle
    });
    return true;
  }

  if (message.type === 'meeting_joined') {
    handleMeetingJoined(sender.tab, message.title, message.url);
  } else if (message.type === 'meeting_left') {
    handleMeetingLeft(sender.tab);
  }

  sendResponse({ received: true });
  return true;
});

// =============================================================================
// 会議イベントの処理
// =============================================================================

function handleMeetingJoined(tab, title, url) {
  const meetingTitle = extractMeetingTitle(title);
  const now = Date.now();

  console.log('[Background] Meeting joined:', meetingTitle, 'isInMeeting:', currentMeeting.isInMeeting);

  // 既に会議中の場合
  if (currentMeeting.isInMeeting) {
    // タイトルが更新された場合のみ通知
    if (meetingTitle !== currentMeeting.meetingTitle && meetingTitle !== 'GoogleMeet') {
      console.log(`[Background] Title updated: ${currentMeeting.meetingTitle} -> ${meetingTitle}`);
      currentMeeting.meetingTitle = meetingTitle;
      notifyApp('meeting_title_updated', { meetingTitle: meetingTitle });
    }
    return;
  }

  // 新規会議参加
  console.log(`[Background] New meeting: ${meetingTitle}`);

  currentMeeting = {
    isInMeeting: true,
    meetingTitle: meetingTitle,
    tabId: tab?.id,
    lastNotificationTime: now
  };

  // アプリに通知
  notifyApp('meeting_start', { meetingTitle: meetingTitle, meetingCode: extractMeetingCode(url) });
}

function handleMeetingLeft(tab) {
  const now = Date.now();

  console.log('[Background] Meeting left:', 'isInMeeting:', currentMeeting.isInMeeting, 'tabId:', tab?.id, 'currentTabId:', currentMeeting.tabId);

  // 会議中でない場合は無視
  if (!currentMeeting.isInMeeting) {
    console.log('[Background] Ignoring meeting_left: not in meeting');
    return;
  }

  // 別のタブからの通知は無視
  if (tab?.id && currentMeeting.tabId && tab.id !== currentMeeting.tabId) {
    console.log('[Background] Ignoring meeting_left: different tab');
    return;
  }

  // 短時間（5秒以内）に複数の退出通知が来た場合は無視（誤検知対策）
  if (currentMeeting.lastNotificationTime && (now - currentMeeting.lastNotificationTime) < 5000) {
    console.log('[Background] Ignoring duplicate meeting_left within 5 seconds');
    return;
  }

  console.log(`[Background] Meeting ended: ${currentMeeting.meetingTitle}`);

  // アプリに通知
  notifyApp('meeting_end', { meetingTitle: currentMeeting.meetingTitle });

  currentMeeting = {
    isInMeeting: false,
    meetingTitle: null,
    tabId: null,
    lastNotificationTime: now
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

// 会議コードを抽出
function extractMeetingCode(url) {
  if (!url) return null;
  const match = url.match(/meet\.google\.com\/([a-z]{3}-[a-z]{4}-[a-z]{3})/);
  return match ? match[1] : null;
}

// =============================================================================
// アプリへの通知
// =============================================================================

async function notifyApp(event, data) {
  try {
    console.log(`[Background] Notifying app: ${event}`, data);

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
      console.error(`[Background] App notification failed: ${response.status}`);
    } else {
      console.log(`[Background] App notified successfully: ${event}`);
    }
  } catch (error) {
    console.log(`[Background] App not running or not responding: ${error.message}`);
  }
}

// =============================================================================
// タブ監視（タブが閉じられた場合の検知）
// =============================================================================

chrome.tabs.onRemoved.addListener((tabId) => {
  if (currentMeeting.tabId === tabId && currentMeeting.isInMeeting) {
    console.log('[Background] Meeting tab closed');
    handleMeetingLeft({ id: tabId });
  }
});

console.log('[Background] MeetingRecorder extension loaded');
