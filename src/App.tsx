/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, Suspense, lazy, Component, ErrorInfo, ReactNode } from 'react';
import { Onboarding } from './components/Onboarding.tsx';
import * as api from './api/index.ts';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  Home, 
  Calendar as CalendarIcon, 
  BarChart2, 
  Compass, 
  User as UserIcon,
  Sparkles,
  Users,
  AlertTriangle
} from 'lucide-react';
import { State, Madhhab } from './logic/types.ts';
import * as logic from './logic/index.ts';

import { LanguageProvider, useTranslation } from './i18n/LanguageContext.tsx';
import { CycleProvider, useCycleData } from './contexts/CycleContext.tsx';

import { HapticService } from './services/HapticService.ts';

// Error Boundary Component
interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Uncaught error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-rose-50 flex flex-col items-center justify-center p-8 text-center">
          <AlertTriangle className="w-16 h-16 text-rose-500 mb-4" />
          <h1 className="text-2xl font-serif font-bold text-rose-900 mb-2">Something went wrong</h1>
          <p className="text-rose-700 mb-6 max-w-md">
            We encountered an unexpected error. Please try refreshing the page.
          </p>
          <button 
            onClick={() => window.location.reload()}
            className="px-6 py-3 bg-rose-600 text-white rounded-full font-bold shadow-lg shadow-rose-200"
          >
            Refresh App
          </button>
          {process.env.NODE_ENV === 'development' && (
            <pre className="mt-8 p-4 bg-black/5 rounded text-left text-xs overflow-auto max-w-full">
              {this.state.error?.message}
            </pre>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}

// Lazy load tab components
const Today = lazy(() => import('./components/Today.tsx').then(m => ({ default: m.Today })));
const Calendar = lazy(() => import('./components/Calendar.tsx').then(m => ({ default: m.Calendar })));
const Discover = lazy(() => import('./components/Discover.tsx').then(m => ({ default: m.Discover })));
const Profile = lazy(() => import('./components/Profile.tsx').then(m => ({ default: m.Profile })));
const Insights = lazy(() => import('./components/Insights.tsx').then(m => ({ default: m.Insights })));
const NiswahAI = lazy(() => import('./components/NiswahAI.tsx').then(m => ({ default: m.NiswahAI })));
const GhuslGuide = lazy(() => import('./components/GhuslGuide.tsx').then(m => ({ default: m.GhuslGuide })));
const GuidedJourneys = lazy(() => import('./components/GuidedJourneys.tsx').then(m => ({ default: m.GuidedJourneys })));
const DreamInterpreter = lazy(() => import('./components/DreamInterpreter.tsx').then(m => ({ default: m.DreamInterpreter })));
const Community = lazy(() => import('./components/Community.tsx').then(m => ({ default: m.Community })));

type Tab = 'today' | 'calendar' | 'insights' | 'discover' | 'community' | 'profile';

const LoadingSpinner = () => {
  const { t } = useTranslation();
  return (
    <div className="flex items-center justify-center p-12">
      <motion.div 
        animate={{ rotate: 360 }}
        transition={{ repeat: Infinity, duration: 1, ease: 'linear' }}
        className="w-8 h-8 border-4 border-rose-500 border-t-transparent rounded-full"
      />
    </div>
  );
};

const LoadingOverlay = () => (
  <div className="fixed inset-0 z-[500] bg-white/80 backdrop-blur-sm flex flex-col items-center justify-center space-y-4">
    <motion.div 
      animate={{ rotate: 360 }}
      transition={{ repeat: Infinity, duration: 1, ease: 'linear' }}
      className="w-10 h-10 border-4 border-rose-500 border-t-transparent rounded-full"
    />
    <p className="text-xs font-bold text-rose-900 uppercase tracking-widest animate-pulse">جاري التحميل...</p>
  </div>
);

import { notificationService } from './services/NotificationService.ts';

function AppContent() {
  const { fiqhState, currentDay: cycleDay, user: contextUser, refresh } = useCycleData();
  const [showOnboarding, setShowOnboarding] = useState(true);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<Tab>('today');
  const [isAIChatOpen, setIsAIChatOpen] = useState(false);
  const [isGhuslOpen, setIsGhuslOpen] = useState(false);
  const [isJourneysOpen, setIsJourneysOpen] = useState(false);
  const [isDreamInterpreterOpen, setIsDreamInterpreterOpen] = useState(false);
  const [user, setUser] = useState<any>(null);
  const { t, isRTL } = useTranslation();

  useEffect(() => {
    if (contextUser) {
      setUser(contextUser);
      if (contextUser.madhhab) {
        setShowOnboarding(false);
      }
      setLoading(false);
    }
  }, [contextUser]);

  useEffect(() => {
    async function checkUser() {
      try {
        let { data: userData, error } = await api.getUser();
        
        if (error === 'Not authenticated') {
          const { data: authData, error: authError } = await api.signInAnonymously();
          
          if (authError) {
            console.error("Anonymous login failed", authError);
            alert(t('error_auth_failed') || "Authentication failed. Please check your internet connection.");
            // Allow proceeding in demo mode for UI exploration
            setLoading(false);
            return;
          }
          
          const { data: newUserData, error: newUserError } = await api.getUser();
          if (newUserError && newUserError !== 'Not authenticated') {
            console.error("Failed to get user after auth", newUserError);
          }
          userData = newUserData;
        }

        if (userData && userData.madhhab) {
          setUser(userData);
          setShowOnboarding(false);
        }
      } catch (err) {
        console.error("Auth check failed", err);
      } finally {
        setLoading(false);
      }
    }
    checkUser();
  }, []);

  useEffect(() => {
    (window as any).openDreamInterpreter = () => setIsDreamInterpreterOpen(true);
    return () => {
      delete (window as any).openDreamInterpreter;
    };
  }, []);

  if (loading) {
    return (
      <div className="fixed inset-0 bg-[#FDFCFB] flex items-center justify-center">
        <motion.div 
          animate={{ rotate: 360 }}
          transition={{ repeat: Infinity, duration: 1, ease: 'linear' }}
          className="w-8 h-8 border-4 border-rose-500 border-t-transparent rounded-full"
        />
      </div>
    );
  }

  if (showOnboarding) {
    return <Onboarding onFinish={async (userData) => {
      setUser(userData);
      await refresh();
      setShowOnboarding(false);
    }} />;
  }

  const renderTab = () => {
    switch (activeTab) {
      case 'today':
        return (
          <Today 
            onOpenAI={() => setIsAIChatOpen(true)} 
            onOpenDreamInterpreter={() => setIsDreamInterpreterOpen(true)}
            onOpenSettings={() => setActiveTab('profile')}
          />
        );
      case 'calendar':
        return <Calendar />;
      case 'insights':
        return <Insights />;
      case 'community':
        return <Community />;
      case 'profile':
        return (
          <Profile 
            onOpenGhusl={() => setIsGhuslOpen(true)}
            onOpenJourneys={() => setIsJourneysOpen(true)}
            onOpenAdah={() => setActiveTab('insights')}
          />
        );
      default:
        return (
          <Today 
            onOpenAI={() => setIsAIChatOpen(true)} 
            onOpenDreamInterpreter={() => setIsDreamInterpreterOpen(true)}
            onOpenSettings={() => setActiveTab('profile')}
          />
        );
    }
  };

  return (
    <div className="min-h-screen bg-[#f1ebeb] px-0">
      <div className="mx-auto min-h-screen w-full max-w-[480px] bg-[#FDFCFB] shadow-[0_0_0_1px_rgba(15,23,42,0.04)]">
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -10 }}
            transition={{ duration: 0.3 }}
            className="pb-28"
          >
            <Suspense fallback={<LoadingSpinner />}>
              {renderTab()}
            </Suspense>
          </motion.div>
        </AnimatePresence>

        <div className="pointer-events-none fixed inset-x-0 bottom-0 z-[100] flex justify-center">
          <nav className="pointer-events-auto mx-auto flex w-full max-w-[480px] items-center justify-between border-t border-black/5 bg-white/80 px-6 pt-3 pb-8 backdrop-blur-xl shadow-[0_-10px_30px_rgba(15,23,42,0.04)]">
            <TabButton 
              active={activeTab === 'today'} 
              onClick={() => setActiveTab('today')} 
              icon={Home} 
              label={t('today')} 
            />
            <TabButton 
              active={activeTab === 'calendar'} 
              onClick={() => setActiveTab('calendar')} 
              icon={CalendarIcon} 
              label={t('calendar')} 
            />
            <TabButton 
              active={activeTab === 'insights'} 
              onClick={() => setActiveTab('insights')} 
              icon={BarChart2} 
              label={t('insights')} 
            />
            
            <motion.button
              whileTap={{ scale: 0.9 }}
              onClick={() => setIsAIChatOpen(true)}
              className="relative -mt-10 flex h-14 w-14 items-center justify-center overflow-hidden rounded-full border-4 border-[#FDFCFB] bg-[var(--color-brand-primary)] shadow-[0_15px_35px_rgba(184,50,95,0.35)]"
            >
              <motion.div 
                animate={{ rotate: 360 }}
                transition={{ repeat: Infinity, duration: 8, ease: 'linear' }}
                className="absolute inset-0 bg-gradient-to-tr from-rose-400 to-pink-600 opacity-80"
              />
              <Sparkles className="relative z-10 h-6 w-6 text-white" />
            </motion.button>

            <TabButton 
              active={activeTab === 'community'} 
              onClick={() => setActiveTab('community')} 
              icon={Users} 
              label={t('community')} 
            />
            <TabButton 
              active={activeTab === 'profile'} 
              onClick={() => setActiveTab('profile')} 
              icon={UserIcon} 
              label={t('profile')} 
            />
          </nav>
        </div>

        <Suspense fallback={<LoadingOverlay />}>
          <NiswahAI 
            isOpen={isAIChatOpen} 
            onClose={() => setIsAIChatOpen(false)} 
            userContext={{
              madhhab: user?.madhhab || 'HANAFI',
              fiqh_state: fiqhState,
              cycle_day: cycleDay,
              conditions: user?.conditions || [],
              ramadan_active: false,
              pregnant: user?.pregnant || false
            }}
          />
        </Suspense>

        <Suspense fallback={<LoadingOverlay />}>
          <GhuslGuide 
            isOpen={isGhuslOpen} 
            onClose={() => setIsGhuslOpen(false)} 
            onComplete={() => {
              setIsGhuslOpen(false);
              if (contextUser) {
                notificationService.scheduleGhuslReminder(contextUser);
              }
              refresh();
            }}
            madhhab={user?.madhhab || 'HANAFI'}
          />
        </Suspense>

        <Suspense fallback={<LoadingOverlay />}>
          <GuidedJourneys 
            isOpen={isJourneysOpen} 
            onClose={() => setIsJourneysOpen(false)} 
            isPremium={true}
          />
        </Suspense>

        <Suspense fallback={<LoadingOverlay />}>
          <DreamInterpreter 
            isOpen={isDreamInterpreterOpen} 
            onClose={() => setIsDreamInterpreterOpen(false)} 
            userMadhhab={contextUser?.madhhab || 'HANAFI'}
          />
        </Suspense>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <LanguageProvider>
        <CycleProvider>
          <AppContent />
        </CycleProvider>
      </LanguageProvider>
    </ErrorBoundary>
  );
}

function TabButton({ active, onClick, icon: Icon, label }: { active: boolean, onClick: () => void, icon: any, label: string }) {
  return (
    <button 
      onClick={() => {
        HapticService.light();
        onClick();
      }}
      className="flex flex-col items-center space-y-1 relative"
    >
      <Icon className={`w-6 h-6 transition-colors duration-300 ${active ? 'text-rose-600' : 'text-rose-900/30'}`} />
      <span className={`text-[8px] font-bold uppercase tracking-widest transition-colors duration-300 ${active ? 'text-rose-600' : 'text-rose-900/30'}`}>
        {label}
      </span>
      {active && (
        <motion.div 
          layoutId="tab-dot"
          className="absolute -bottom-2 w-1 h-1 bg-rose-600 rounded-full"
        />
      )}
    </button>
  );
}

