import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import * as Sentry from '@sentry/nextjs'

import { RAILS_API_URL, WEB_PUSH_PUBLIC_KEY } from '@campsite/config'

import { apiClient } from '@/utils/queryClient'

interface ContextProps {
  subscribe: () => Promise<void>
  unsubscribe: () => Promise<void>
  permission: NotificationPermission
}

const WebPushContext = createContext<ContextProps>({
  subscribe: () => Promise.resolve(),
  unsubscribe: () => Promise.resolve(),
  permission: 'default'
})

interface Props {
  children: React.ReactNode
}

// @ts-ignore
const conv = (val) => btoa(String.fromCharCode.apply(null, new Uint8Array(val)))

export const WebPushProvider: React.FC<Props> = ({ children }) => {
  const [permission, setPermission] = useState(() => ('Notification' in window ? Notification.permission : 'denied'))
  const [pushManager, setPushManager] = useState<PushManager | null>(null)

  useEffect(() => {
    if ('permissions' in navigator && 'query' in navigator.permissions) {
      navigator.permissions
        .query({ name: 'notifications' })
        .then((status) => {
          status.onchange = () => {
            setPermission(status.state === 'prompt' ? 'default' : status.state)
          }
        })
        .catch(() => setPermission('denied'))
    }
  }, [])

  useEffect(() => {
    if (!pushManager) {
      console.log('[WebPush] No pushManager available yet, skipping subscription setup')
      return
    }

    const run = async () => {
      console.log('[WebPush] Running subscription logic, permission:', permission)
      const existingSubscription = await pushManager.getSubscription()

      console.log('[WebPush] Existing subscription:', existingSubscription)

      if (permission === 'granted') {
        // already registered a subscription
        if (existingSubscription) {
          console.log('[WebPush] Already has subscription, skipping creation')
          return
        }

        console.log('[WebPush] Creating new push subscription...')
        const subscription = await pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: WEB_PUSH_PUBLIC_KEY
        })

        console.log('[WebPush] Subscription created:', subscription)
        
        const p256dh = conv(subscription.getKey('p256dh'))
        const auth = conv(subscription.getKey('auth'))

        console.log('[WebPush] Sending subscription to backend...')
        await apiClient.pushSubscriptions.postPushSubscriptions().request({
          new_endpoint: subscription.endpoint,
          p256dh,
          auth
        })
        console.log('[WebPush] Subscription sent to backend successfully')
      } else if (permission === 'denied' && existingSubscription) {
        // eslint-disable-next-line no-console
        console.log('[WebPush] Permission denied, unsubscribing...')
        await existingSubscription.unsubscribe()
      }
    }

    run().catch((error) => {
      console.error('[WebPush] Error in subscription logic:', error)
    })
  }, [permission, pushManager])

  useEffect(() => {
    // Register service worker ALWAYS (not just in PWA mode)
    // This allows the install prompt to appear
    if ('serviceWorker' in navigator) {
      console.log('[WebPush] Attempting to register service worker...')
      navigator.serviceWorker
        .register(`/service_worker.js?API_URL=${RAILS_API_URL}`)
        .then(
          (registration) => {
            console.log('[WebPush] Service worker registered successfully:', registration)
            if ('pushManager' in registration) {
              console.log('[WebPush] PushManager available, setting it...')
              setPushManager(registration.pushManager)
            } else {
              console.warn('[WebPush] PushManager not available in registration')
            }
          },
          (error) => {
            console.error('[WebPush] Service Worker registration failed:', error)
            Sentry.captureException(`Service Worker registration failed: ${error}`)
          }
        )
    } else {
      console.warn('[WebPush] Service Worker not supported in this browser/context')
    }
  }, []) // Only run once on mount, not dependent on canPush

  const value = useMemo(() => {
    return {
      subscribe: async () => {
        const permissions = await Notification.requestPermission()

        setPermission(permissions)
      },
      unsubscribe: async () => {
        if (!pushManager) return
        const subscription = await pushManager.getSubscription()

        await subscription?.unsubscribe()
      },
      permission
    }
  }, [pushManager, permission])

  return <WebPushContext.Provider value={value}>{children}</WebPushContext.Provider>
}

export const useWebPush = (): ContextProps => useContext(WebPushContext)
