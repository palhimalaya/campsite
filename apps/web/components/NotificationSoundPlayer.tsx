import { useEffect, useRef } from 'react'

/**
 * Component that listens for messages from the service worker
 * to play notification sounds when push notifications are received
 */
export function NotificationSoundPlayer() {
  const audioRef = useRef<HTMLAudioElement | null>(null)

  useEffect(() => {
    // Create audio element for notification sound
    audioRef.current = new Audio('/sounds/call-peer-join.mp3')
    audioRef.current.volume = 0.5 // Adjust volume as needed

    // Listen for messages from service worker
    const handleMessage = (event: MessageEvent) => {
      if (event.data?.type === 'PLAY_NOTIFICATION_SOUND') {
        // Play the notification sound
        audioRef.current?.play().catch((error) => {
          // eslint-disable-next-line no-console
          console.error('Failed to play notification sound:', error)
        })
      }
    }

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('message', handleMessage)
    }

    return () => {
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.removeEventListener('message', handleMessage)
      }
    }
  }, [])

  return null // This component doesn't render anything
}
