/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useMemo, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  BarChart2, 
  TrendingUp, 
  Activity, 
  Calendar as CalendarIcon,
  ChevronRight,
  Sparkles,
  Heart,
  Brain,
  Wind,
  Zap,
  Moon,
  ArrowUpRight,
  ArrowDownRight,
  Minus
} from 'lucide-react';
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer,
  Cell,
  AreaChart,
  Area
} from 'recharts';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { useCycleData } from '../contexts/CycleContext.tsx';
import { cn } from '../utils/cn.ts';

const SYMPTOM_DATA = [
  { key: 'cramps', value: 85, color: '#FF5C8D', trend: 'up', icon: Activity },
  { key: 'headache', value: 45, color: '#4FC3F7', trend: 'down', icon: Brain },
  { key: 'mood', value: 65, color: '#9575CD', trend: 'stable', icon: Heart },
  { key: 'energy', value: 30, color: '#81C784', trend: 'up', icon: Zap },
  { key: 'sleep', value: 55, color: '#FFD54F', trend: 'down', icon: Moon },
];

export const Insights = () => {
  const { t, isRTL } = useTranslation();
  const { user, ledger, cycleStats, loading } = useCycleData();
  const [selectedHistory, setSelectedHistory] = useState<any>(null);

  const translatedData = useMemo(() => 
    SYMPTOM_DATA.map(item => ({
      ...item,
      name: t(item.key as any)
    })), [t]);

  const avgCycleLength = cycleStats.avgCycleLength === null ? null : Math.round(cycleStats.avgCycleLength);
  const regularityScore = cycleStats.regularity || 0;

  if (loading) return (
    <div className="flex items-center justify-center p-12">
      <motion.div animate={{ rotate: 360 }} transition={{ repeat: Infinity, duration: 1, ease: 'linear' }} className="w-8 h-8 border-4 border-rose-500 border-t-transparent rounded-full" />
    </div>
  );

  return (
    <div className={cn("flex flex-col min-h-screen bg-[#FDFCFB] pb-32", isRTL && "font-arabic")}>
      {/* Header */}
      <header className="p-6 pt-12 space-y-2">
        <h1 className="text-3xl font-serif font-bold text-[#8E244D]">{t('insights')}</h1>
        <p className="text-sm text-gray-400">{t('insights_desc')}</p>
      </header>

      <main className="px-6 space-y-8">
        {/* Summary Stats */}
        <section className="grid grid-cols-2 gap-4">
          <div className="bg-white p-5 rounded-[32px] shadow-sm border border-black/5 space-y-1">
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('avg_cycle_length')}</p>
            <div className="flex items-baseline space-x-1 rtl:space-x-reverse">
              <span className="text-2xl font-serif font-bold text-rose-600">{avgCycleLength === null ? '—' : avgCycleLength.toLocaleString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US')}</span>
              {avgCycleLength !== null && <span className="text-xs text-gray-400">{t('days')}</span>}
            </div>
          </div>
          <div className="bg-white p-5 rounded-[32px] shadow-sm border border-black/5 space-y-1">
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('regularity')}</p>
            <div className="flex items-baseline space-x-1 rtl:space-x-reverse">
              <span className="text-2xl font-serif font-bold text-emerald-600">
                {cycleStats.regularity !== null ? `${cycleStats.regularity.toLocaleString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US')}%` : '—'}
              </span>
              {cycleStats.regularity !== null && <span className="text-xs text-gray-400">{t('high' as any)}</span>}
            </div>
          </div>
        </section>

        {/* Symptom Trends Enhanced */}
        <section className="bg-white rounded-[32px] p-6 shadow-xl shadow-black/5 border border-black/5 space-y-8">
          <div className="flex items-center justify-between">
            <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-2" : "space-x-2")}>
              <TrendingUp className="w-5 h-5 text-[#FF5C8D]" />
              <h3 className="text-sm font-bold text-gray-800">{t('symptom_trends')}</h3>
            </div>
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('last_3_months')}</span>
          </div>

          <div className="space-y-6">
            {translatedData.map((item, i) => (
              <div key={item.key} className="space-y-2">
                <div className="flex items-center justify-between">
                  <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-2" : "space-x-2")}>
                    <div className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ backgroundColor: `${item.color}1A`, color: item.color }}>
                      <item.icon className="w-4 h-4" />
                    </div>
                    <span className="text-xs font-bold text-gray-700">{item.name}</span>
                  </div>
                  <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-2" : "space-x-2")}>
                    <span className="text-[10px] font-bold text-gray-400">{item.value.toLocaleString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US')}%</span>
                    {item.trend === 'up' && <ArrowUpRight className="w-3 h-3 text-rose-400" />}
                    {item.trend === 'down' && <ArrowDownRight className="w-3 h-3 text-emerald-400" />}
                    {item.trend === 'stable' && <Minus className="w-3 h-3 text-gray-300" />}
                  </div>
                </div>
                <div className="h-2 w-full bg-gray-50 rounded-full overflow-hidden">
                  <motion.div 
                    initial={{ width: 0 }}
                    animate={{ width: `${item.value}%` }}
                    transition={{ duration: 1, delay: i * 0.1 }}
                    className="h-full rounded-full"
                    style={{ backgroundColor: item.color }}
                  />
                </div>
              </div>
            ))}
          </div>

          <div className="pt-4 border-t border-black/5">
            <p className="text-[11px] text-gray-400 leading-relaxed italic">
              {t('mood_pattern_desc')}
            </p>
          </div>
        </section>

        {/* Cycle Regularity Dot Matrix */}
        <section className="bg-white rounded-[32px] p-6 shadow-xl shadow-black/5 border border-black/5 space-y-6">
          <div className="flex items-center justify-between">
            <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-2" : "space-x-2")}>
              <BarChart2 className="w-5 h-5 text-emerald-500" />
              <h3 className="text-sm font-bold text-gray-800">{t('cycle_regularity')}</h3>
            </div>
            <div className="flex space-x-1 rtl:space-x-reverse">
              <div className="w-2 h-2 rounded-full bg-emerald-500" />
              <div className="w-2 h-2 rounded-full bg-gray-100" />
            </div>
          </div>

          <div className="grid grid-cols-10 gap-2">
            {Array.from({ length: 30 }).map((_, i) => {
              const isActive = i < (regularityScore / 3.33);
              return (
                <motion.div 
                  key={i}
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ delay: i * 0.01 }}
                  className={cn(
                    "aspect-square rounded-full",
                    isActive ? "bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.3)]" : "bg-gray-100"
                  )}
                />
              );
            })}
          </div>
          
          <p className="text-[10px] text-gray-400 text-center font-medium">
            {cycleStats.regularity === null ? t('insufficient_data_for_calculation') : t('cycle_regularity_desc')}
          </p>
        </section>

        {/* AI Insights Cards */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('health_insights')}</h3>
          <div className="space-y-3">
            <InsightCard 
              icon={Brain} 
              title={t('mood_pattern_detected')} 
              desc={t('mood_pattern_desc')}
              color="bg-purple-50 text-purple-600"
              isRTL={isRTL}
            />
            <InsightCard 
              icon={Wind} 
              title={t('energy_boost_expected')} 
              desc={t('energy_boost_desc')}
              color="bg-emerald-50 text-emerald-600"
              isRTL={isRTL}
            />
            {cycleStats.regularity !== null && (
              <InsightCard 
                icon={Heart} 
                title={t('cycle_regularity_high')} 
                desc={t('cycle_regularity_desc')}
                color="bg-rose-50 text-rose-600"
                isRTL={isRTL}
              />
            )}
          </div>
        </section>

        {/* Cycle History List */}
        <section className="space-y-4">
          <div className="flex items-center justify-between px-2">
            <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('cycle_history')}</h3>
            <button className="text-[10px] font-bold text-[#FF5C8D] uppercase tracking-widest">{t('view_all')}</button>
          </div>
          
          <div className="bg-white rounded-[32px] overflow-hidden shadow-xl shadow-black/5 border border-black/5">
            {ledger.length === 0 ? (
              <div className="p-12 text-center space-y-2">
                <CalendarIcon className="w-12 h-12 text-gray-200 mx-auto" />
                <p className="text-sm text-gray-400 font-medium">{t('no_cycle_history_yet')}</p>
              </div>
            ) : (
              ledger.slice(0, 5).map((record, i) => (
                <HistoryItem 
                  key={record.cycle_number}
                  startDate={new Date(record.haid_start)} 
                  endDate={record.haid_end ? new Date(record.haid_end) : null} 
                  durationDays={Math.round(record.haid_duration_hours / 24)} 
                  cycleDays={record.tuhr_duration_days + Math.round(record.haid_duration_hours / 24)} 
                  isRTL={isRTL}
                  t={t}
                  last={i === Math.min(ledger.length, 5) - 1}
                  onClick={() => setSelectedHistory({ 
                    startDate: new Date(record.haid_start),
                    endDate: record.haid_end ? new Date(record.haid_end) : null,
                    durationDays: Math.round(record.haid_duration_hours / 24),
                    cycleDays: record.tuhr_duration_days + Math.round(record.haid_duration_hours / 24)
                  })}
                />
              ))
            )}
          </div>
        </section>

        {/* History Detail Sheet */}
        <AnimatePresence>
          {selectedHistory && (
            <>
              <motion.div 
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onClick={() => setSelectedHistory(null)}
                className="fixed inset-0 bg-black/40 z-[200] backdrop-blur-sm"
              />
              <motion.div 
                initial={{ y: '100%' }}
                animate={{ y: 0 }}
                exit={{ y: '100%' }}
                className="fixed bottom-0 left-0 right-0 bg-white rounded-t-[40px] z-[201] p-8 space-y-6"
              >
                <div className="w-12 h-1.5 bg-gray-100 rounded-full mx-auto" />
                <div className="space-y-4">
                  <h3 className="text-2xl font-serif font-bold text-rose-800">{t('cycle_history_details')}</h3>
                  
                  <div className="grid grid-cols-2 gap-4">
                    <div className="p-4 bg-rose-50 rounded-2xl">
                      <p className="text-[10px] font-bold text-rose-400 uppercase tracking-widest mb-1">{t('start_of_cycle' as any)}</p>
                      <p className="text-sm font-bold text-rose-800">
                        {new Intl.DateTimeFormat(isRTL ? 'ar-SA-u-nu-latn' : 'en-US', { day: 'numeric', month: 'long' }).format(selectedHistory.startDate)}
                      </p>
                    </div>
                    <div className="p-4 bg-emerald-50 rounded-2xl">
                      <p className="text-[10px] font-bold text-emerald-400 uppercase tracking-widest mb-1">{t('duration' as any)}</p>
                      <p className="text-sm font-bold text-emerald-800">
                        {isRTL 
                          ? `${selectedHistory.durationDays.toLocaleString('en-US')} أيام` 
                          : `${selectedHistory.durationDays} days`}
                      </p>
                    </div>
                  </div>

                  <div className="p-6 bg-gray-50 rounded-[32px] space-y-3">
                    <h4 className="text-sm font-bold text-gray-800">{t('guidance' as any)}</h4>
                    <p className="text-xs text-gray-500 leading-relaxed rtl:text-right">
                      {t('cycle_history_details_desc' as any) || "This cycle was regular. Your average duration is 5 days. Tracking consistently helps Niswah AI provide better predictions."}
                    </p>
                  </div>

                  <button 
                    onClick={() => setSelectedHistory(null)}
                    className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold"
                  >
                    {t('close' as any)}
                  </button>
                </div>
              </motion.div>
            </>
          )}
        </AnimatePresence>
      </main>
    </div>
  );
};

const InsightCard = ({ icon: Icon, title, desc, color, isRTL }: any) => (
  <motion.div 
    whileTap={{ scale: 0.98 }}
    className={cn(
      "bg-white p-5 rounded-[32px] shadow-sm border border-black/5 flex items-start",
      isRTL ? "space-x-reverse space-x-4 text-right" : "space-x-4"
    )}
  >
    <div className={cn("w-12 h-12 rounded-2xl flex items-center justify-center flex-shrink-0", color)}>
      <Icon className="w-6 h-6" />
    </div>
    <div className="space-y-1">
      <h4 className="text-sm font-bold text-gray-800">{title}</h4>
      <p className="text-xs text-gray-400 leading-relaxed">{desc}</p>
    </div>
  </motion.div>
);

const HistoryItem = ({ startDate, endDate, durationDays, cycleDays, last, isRTL, t, onClick }: any) => {
  const locale = isRTL ? 'ar-SA-u-nu-latn' : 'en-US';
  const dateFormatter = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long' });
  const dateRange = `${dateFormatter.format(startDate)} – ${dateFormatter.format(endDate)}`;
  
  const formattedDuration = isRTL 
    ? `${durationDays.toLocaleString('en-US')} أيام` 
    : `${durationDays} days`;
    
  const formattedCycle = isRTL
    ? `${cycleDays.toLocaleString('en-US')} يوماً`
    : `${cycleDays} days`;

  return (
    <div 
      onClick={onClick}
      className={cn(
        "p-6 flex items-center justify-between hover:bg-gray-50 transition-colors cursor-pointer",
        !last && "border-b border-black/5",
        isRTL && "flex-row-reverse"
      )}
    >
      {/* Right side in RTL (Primary) */}
      <div className={cn("flex items-center", isRTL ? "flex-row-reverse space-x-reverse space-x-4" : "space-x-4")}>
        <div className={isRTL ? "text-right" : "text-left"}>
          <p className="text-sm font-bold text-gray-800">{dateRange}</p>
          <p className="text-[10px] text-gray-400 font-medium uppercase tracking-widest">{formattedDuration}</p>
          <p className="text-[9px] text-[#FF5C8D] font-bold mt-1">{t('view_details')}</p>
        </div>
        <div className="w-10 h-10 bg-rose-50 rounded-xl flex items-center justify-center text-rose-400">
          <CalendarIcon className="w-5 h-5" />
        </div>
      </div>

      {/* Left side in RTL (Secondary) */}
      <div className={cn("flex items-center", isRTL ? "flex-row-reverse space-x-reverse space-x-3" : "space-x-3")}>
        <div className={isRTL ? "text-left" : "text-right"}>
          <p className="text-[8px] text-gray-400 font-bold uppercase tracking-widest">{t('cycle_length')}</p>
          <p className="text-xs font-bold text-gray-800">{formattedCycle}</p>
        </div>
        <ChevronRight className={cn("w-4 h-4 text-gray-300", isRTL && "rotate-180")} />
      </div>
    </div>
  );
};
