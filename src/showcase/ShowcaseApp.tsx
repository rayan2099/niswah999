import React, { Suspense } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Home, Calendar as CalendarIcon, BarChart2, User as UserIcon, Sparkles, Users } from 'lucide-react';
import { LanguageProvider } from '../i18n/LanguageContext.tsx';
import { DemoCycleProvider } from './DemoCycleProvider.tsx';
import { Today } from '../components/Today.tsx';
import { Calendar } from '../components/Calendar.tsx';
import { Insights } from '../components/Insights.tsx';
import { Community } from '../components/Community.tsx';
import { NiswahAI } from '../components/NiswahAI.tsx';

export type ShowcaseFeature = 'today' | 'calendar' | 'insights' | 'ai' | 'fiqh' | 'pregnancy' | 'community';

export function ShowcaseApp({ feature = 'today' }: { feature?: ShowcaseFeature }) {
  React.useEffect(() => {
    localStorage.setItem('app_language', 'ar');
    document.documentElement.dir = 'rtl';
    document.documentElement.lang = 'ar';
  }, []);

  return (
    <LanguageProvider>
      <DemoCycleProvider pregnant={feature === 'pregnancy'}>
        <ShowcaseContent feature={feature} />
      </DemoCycleProvider>
    </LanguageProvider>
  );
}

function ShowcaseContent({ feature }: { feature: ShowcaseFeature }) {
  const tab = feature === 'fiqh' || feature === 'pregnancy' || feature === 'ai' ? 'today' : feature;
  const content = (() => {
    if (feature === 'calendar') return <Calendar />;
    if (feature === 'insights') return <Insights />;
    if (feature === 'community') return <Community />;
    return <Today onOpenAI={() => {}} onOpenDreamInterpreter={() => {}} onOpenSettings={() => {}} />;
  })();

  return (
    <div className="relative min-h-screen bg-[#FDFCFB]">
      <AnimatePresence mode="wait">
        <motion.div
          key={feature}
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -10 }}
          transition={{ duration: 0.3 }}
          className="pb-28"
        >
          <Suspense fallback={<div className="p-12 text-center text-rose-500">...</div>}>
            {content}
          </Suspense>
        </motion.div>
      </AnimatePresence>

      <div className="pointer-events-none absolute inset-x-0 bottom-0 z-[100] flex justify-center">
        <nav className="pointer-events-auto mx-auto flex w-full items-center justify-between border-t border-black/5 bg-white/80 px-6 pt-3 pb-8 backdrop-blur-xl shadow-[0_-10px_30px_rgba(15,23,42,0.04)]">
          <Tab active={tab === 'today'} icon={Home} label="اليوم" />
          <Tab active={tab === 'calendar'} icon={CalendarIcon} label="التقويم" />
          <Tab active={tab === 'insights'} icon={BarChart2} label="التحليلات" />
          <motion.div className="relative -mt-10 flex h-14 w-14 items-center justify-center overflow-hidden rounded-full border-4 border-[#FDFCFB] bg-rose-600 shadow-[0_15px_35px_rgba(184,50,95,0.35)]">
            <motion.div animate={{ rotate: 360 }} transition={{ repeat: Infinity, duration: 8, ease: 'linear' }} className="absolute inset-0 bg-gradient-to-tr from-rose-400 to-pink-600 opacity-80" />
            <Sparkles className="relative z-10 h-6 w-6 text-white" />
          </motion.div>
          <Tab active={tab === 'community'} icon={Users} label="المجتمع" />
          <Tab active={false} icon={UserIcon} label="الحساب" />
        </nav>
      </div>

      {feature === 'ai' && (
        <NiswahAI
          isOpen={true}
          onClose={() => {}}
          userContext={{ madhhab: 'HANAFI', fiqh_state: 'TAHARA', cycle_day: 12, conditions: [], ramadan_active: false, pregnant: false }}
        />
      )}
    </div>
  );
}

function Tab({ active, icon: Icon, label }: { active: boolean; icon: any; label: string }) {
  return (
    <div className="relative flex flex-col items-center space-y-1">
      <Icon className={`h-6 w-6 transition-colors duration-300 ${active ? 'text-rose-600' : 'text-rose-900/30'}`} />
      <span className={`text-[8px] font-bold uppercase tracking-widest transition-colors duration-300 ${active ? 'text-rose-600' : 'text-rose-900/30'}`}>{label}</span>
      {active && <motion.div layoutId="showcase-tab-dot" className="absolute -bottom-2 h-1 w-1 rounded-full bg-rose-600" />}
    </div>
  );
}
