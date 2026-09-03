/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  ChevronLeft, 
  ChevronRight, 
  Calendar as CalendarIcon,
  Info,
  Droplets,
  Sparkles,
  Heart
} from 'lucide-react';
import { 
  format, 
  startOfMonth, 
  endOfMonth, 
  startOfWeek, 
  endOfWeek, 
  eachDayOfInterval, 
  isSameMonth, 
  isSameDay, 
  addMonths, 
  subMonths,
  isToday,
  parseISO,
  addDays,
  differenceInDays
} from 'date-fns';
import { ResponsiveContainer, AreaChart, Area, XAxis, ReferenceLine, ReferenceArea } from 'recharts';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { useCycleData } from '../contexts/CycleContext.tsx';
import * as api from '../api/index.ts';
import { DBCycleEntry } from '../api/db-types.ts';
import { State, STATE_COLORS, User } from '../logic/types.ts';
import { cn } from '../utils/cn.ts';

import * as logic from '../logic/index.ts';

import { toHijri } from 'hijri-converter';

const hijriMonthNames = [
  "Muharram", "Safar", "Rabi' al-awwal", "Rabi' al-thani",
  "Jumada al-ula", "Jumada al-akhira", "Rajab", "Sha'ban",
  "Ramadan", "Shawwal", "Dhu al-Qi'dah", "Dhu al-Hijjah"
];

const hijriMonthNamesAr = [
  "محرم", "صفر", "ربيع الأول", "ربيع الثاني",
  "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان",
  "رمضان", "شوال", "ذو القعدة", "ذو الحجة"
];

export const Calendar = () => {
  const { t, isRTL } = useTranslation();
  const { user, entries, cycleStats, prediction, ovulation, loading: dataLoading } = useCycleData();
  const [currentDate, setCurrentDate] = useState(new Date());

  const cycleLength = cycleStats.avgCycleLength;

  const monthEntries = useMemo(() => {
    const month = currentDate.getMonth();
    const year = currentDate.getFullYear();
    return entries.filter(e => {
      const d = parseISO(e.date);
      return d.getMonth() === month && d.getFullYear() === year;
    });
  }, [entries, currentDate]);

  const haidDays = useMemo(() => monthEntries.filter(e => e.fiqh_state === 'HAID').length, [monthEntries]);
  const taharaDays = useMemo(() => monthEntries.filter(e => e.fiqh_state === 'TAHARA').length, [monthEntries]);
  const hasBloodLogged = useMemo(() => monthEntries.some(e => e.flow_intensity && e.flow_intensity !== 'none'), [monthEntries]);
  const isHanafiPending = user?.madhhab === 'HANAFI' && user?.pendingBloodStart;

  const cycleDates = useMemo(() => {
    if (!user || !prediction || !ovulation || !cycleStats.lastPeriodDate) return null;
    
    return { 
      start: parseISO(cycleStats.lastPeriodDate), 
      ovulation: new Date(ovulation.predictedOvulationDate), 
      next: new Date(prediction.predictedStartDate),
      fertileStart: new Date(ovulation.fertileWindowStart),
      fertileEnd: new Date(ovulation.fertileWindowEnd)
    };
  }, [user, prediction, ovulation, cycleStats.lastPeriodDate]);

  const pregnancyData = useMemo(() => {
    if (cycleLength === null) return [];
    const peakDay = Math.round(cycleLength) - 14;
    return Array.from({ length: Math.round(cycleLength) }, (_, i) => {
      const day = i + 1;
      // Normal distribution centered around peakDay
      const chance = Math.exp(-Math.pow(day - peakDay, 2) / 15) * 100;
      return { day, chance };
    });
  }, [cycleLength]);

  const monthStart = startOfMonth(currentDate);
  const monthEnd = endOfMonth(monthStart);
  const startDate = startOfWeek(monthStart);
  const endDate = endOfWeek(monthEnd);

  const calendarDays = eachDayOfInterval({
    start: startDate,
    end: endDate,
  });

  const nextMonth = () => setCurrentDate(addMonths(currentDate, 1));
  const prevMonth = () => setCurrentDate(subMonths(currentDate, 1));

  const getDayState = (day: Date): { state: State | null; isExpected?: boolean; isFertile?: boolean; isOvulation?: boolean } => {
    const dayString = format(day, 'yyyy-MM-dd');
    const entry = entries.find(e => e.date === dayString);
    if (entry) return { state: entry.fiqh_state as State };
    
    // Prediction logic using cycleStats
    if (user && cycleStats.lastPeriodDate && cycleLength !== null) {
      const lastPeriod = parseISO(cycleStats.lastPeriodDate);
      const diff = differenceInDays(day, lastPeriod);
      const dayInCycle = diff % Math.round(cycleLength);
      
      if (cycleStats.avgPeriodLength !== null && dayInCycle >= 0 && dayInCycle < Math.round(cycleStats.avgPeriodLength)) return { state: 'HAID', isExpected: true };
      
      if (ovulation) {
        const fertileStart = new Date(ovulation.fertileWindowStart);
        const fertileEnd = new Date(ovulation.fertileWindowEnd);
        const ovulationDay = new Date(ovulation.predictedOvulationDate);
        
        if (isSameDay(day, ovulationDay)) return { state: 'TAHARA', isFertile: true, isOvulation: true };
        if (day >= fertileStart && day <= fertileEnd) return { state: 'TAHARA', isFertile: true };
      }
    }
    
    return { state: null };
  };

  const weekDays = isRTL 
    ? [t('sat'), t('fri'), t('thu'), t('wed'), t('tue'), t('mon'), t('sun')]
    : [t('sun'), t('mon'), t('tue'), t('wed'), t('thu'), t('fri'), t('sat')];

  return (
    <div className="flex flex-col min-h-screen bg-[#FDFCFB] pb-32">
      {/* Header */}
      <header className="p-6 flex items-center justify-between sticky top-0 bg-[#FDFCFB]/80 backdrop-blur-md z-50">
        <h1 className="text-xl font-serif font-bold text-emerald-900">{t('calendar')}</h1>
        <div className="flex items-center space-x-2 bg-white rounded-2xl p-1 shadow-sm border border-black/5">
          <button 
            onClick={prevMonth}
            className="p-2 hover:bg-gray-50 rounded-xl transition-colors"
          >
            <ChevronLeft className={cn("w-5 h-5 text-emerald-900", isRTL && "rotate-180")} />
          </button>
          <span className="px-4 text-sm font-bold text-emerald-900 min-w-[120px] text-center">
            {format(currentDate, 'MMMM yyyy')}
          </span>
          <button 
            onClick={nextMonth}
            className="p-2 hover:bg-gray-50 rounded-xl transition-colors"
          >
            <ChevronRight className={cn("w-5 h-5 text-emerald-900", isRTL && "rotate-180")} />
          </button>
        </div>
      </header>

      <main className="px-6 space-y-8">
        {/* Calendar Grid */}
        <div className="bg-white rounded-[32px] p-6 shadow-xl shadow-black/5 border border-black/5">
          <div className="grid grid-cols-7 mb-4">
            {weekDays.map((day) => (
              <div key={day} className="text-center text-[10px] font-bold text-gray-400 uppercase tracking-widest py-2">
                {day}
              </div>
            ))}
          </div>

          <div className="grid grid-cols-7 gap-y-4">
            {calendarDays.map((day, i) => {
              const { state, isExpected, isFertile, isOvulation } = getDayState(day);
              const isCurrentMonth = isSameMonth(day, monthStart);
              const isTodayDay = isToday(day);
              
              // Calculate Hijri date
              const hijri = toHijri(day.getFullYear(), day.getMonth() + 1, day.getDate());
              const hijriMonthName = isRTL ? hijriMonthNamesAr[hijri.hm - 1] : hijriMonthNames[hijri.hm - 1];
              const hijriDisplay = `${hijri.hd} ${hijriMonthName}`;

              return (
                <motion.div
                  key={day.toString()}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: i * 0.005 }}
                  className={cn(
                    "relative aspect-square flex flex-col items-center justify-center text-sm font-medium transition-all",
                    !isCurrentMonth && "opacity-10",
                    isTodayDay && "text-emerald-600 font-bold"
                  )}
                >
                  {/* Fiqh State Backgrounds */}
                  {state === 'HAID' && (
                    <div className={cn(
                      "absolute inset-1 rounded-full",
                      isExpected ? "border-2 border-[#BE123C] bg-transparent opacity-50" : "bg-[#BE123C]"
                    )} />
                  )}
                  {state === 'TAHARA' && !isFertile && (
                    <div className="absolute inset-1 rounded-full bg-[#0D9488]/10" />
                  )}
                  {state === 'ISTIHADAH' && (
                    <div className="absolute inset-1 rounded-full bg-[#4F46E5]/20 border border-[#4F46E5]/40" />
                  )}
                  {state === 'NIFAS' && (
                    <div className="absolute inset-1 rounded-full bg-[#D97706]" />
                  )}

                  {/* Fertile Markers */}
                  {isFertile && (
                    <div className={cn(
                      "absolute inset-1 rounded-full bg-[#D97706]/10",
                      isOvulation && "border-2 border-[#D97706] scale-110 z-20"
                    )} />
                  )}

                  {/* Today Indicator */}
                  {isTodayDay && (
                    <div className="absolute inset-0 border-2 border-emerald-500 rounded-full z-30" />
                  )}

                  <span className={cn(
                    "relative z-10 text-[13px]",
                    state === 'HAID' && !isExpected && "text-white",
                    isFertile && "text-[#D97706]"
                  )}>
                    {format(day, 'd')}
                  </span>
                  <span className={cn(
                    "relative z-10 text-[8px] opacity-40 mt-0.5 whitespace-nowrap",
                    state === 'HAID' && !isExpected && "text-white opacity-60"
                  )}>
                    {hijriDisplay}
                  </span>
                </motion.div>
              );
            })}
          </div>
        </div>

        {/* Pregnancy Chance Chart */}
        <section className="bg-white rounded-[32px] p-6 shadow-xl shadow-black/5 border border-black/5 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold text-gray-800">{t('chance_of_getting_pregnant')}</h3>
            <span className="text-xs font-bold text-blue-500 uppercase tracking-widest">{t('high')}</span>
          </div>
          
          <div className="h-40 w-full relative">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={pregnancyData} margin={{ top: 20, right: 10, left: 10, bottom: 0 }}>
                <defs>
                  <linearGradient id="colorChance" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#4FC3F7" stopOpacity={0.3}/>
                    <stop offset="95%" stopColor="#4FC3F7" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <XAxis dataKey="day" hide />
                <Area 
                  type="monotone" 
                  dataKey="chance" 
                  stroke="#4FC3F7" 
                  strokeWidth={3}
                  strokeDasharray={(user?.adahConfidence || 0) < 50 ? "5 5" : "0"}
                  fillOpacity={1} 
                  fill="url(#colorChance)" 
                  animationDuration={1000}
                />
                {/* Fertile Window Shading */}
                {cycleDates && (
                  <ReferenceArea 
                    x1={differenceInDays(cycleDates.fertileStart, cycleDates.start) + 1} 
                    x2={differenceInDays(cycleDates.fertileEnd, cycleDates.start) + 1} 
                    fill="#4FC3F7" 
                    fillOpacity={0.1}
                    label={{ position: 'top', value: t('fertile_window'), fontSize: 8, fill: '#4FC3F7', fontWeight: 'bold' }}
                  />
                )}
                {/* Current Day Marker */}
                {cycleStats.currentDay !== null && <ReferenceLine 
                    x={cycleStats.currentDay} 
                    stroke="#10B981" 
                    strokeWidth={2}
                    label={{ position: 'top', value: t('you_are_here'), fontSize: 8, fill: '#10B981', fontWeight: 'bold' }}
                  />}
              </AreaChart>
            </ResponsiveContainer>
          </div>

          <div className="flex justify-between text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2 text-center">
            <div className="flex flex-col">
              <span>{t('start_of_cycle')}</span>
              <span className="text-gray-900 mt-1">
                {cycleDates ? cycleDates.start.toLocaleDateString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US', { day: 'numeric', month: 'long' }) : '—'}
              </span>
            </div>
            <div className="flex flex-col">
              <span>{t('ovulation')}</span>
              <span className="text-gray-900 mt-1">
                {cycleDates ? cycleDates.ovulation.toLocaleDateString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US', { day: 'numeric', month: 'long' }) : '—'}
              </span>
            </div>
            <div className="flex flex-col">
              <span>{t('next_cycle')}</span>
              <span className="text-gray-900 mt-1">
                {cycleDates ? cycleDates.next.toLocaleDateString(isRTL ? 'ar-SA-u-nu-latn' : 'en-US', { day: 'numeric', month: 'long' }) : '—'}
              </span>
            </div>
          </div>

          {(user?.adahConfidence || 0) < 50 && (
            <p className="text-[9px] text-amber-600 font-bold text-center bg-amber-50 py-2 rounded-xl border border-amber-100 italic">
              {t('prediction_improves_with_more_data')}
            </p>
          )}
        </section>

        {/* Legend */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('legend')}</h3>
          <div className="grid grid-cols-2 gap-3">
            <LegendCard color={STATE_COLORS.HAID} label={t('haid')} icon={Droplets} />
            <LegendCard color={STATE_COLORS.TAHARA} label={t('tahara')} icon={Sparkles} />
            <LegendCard color={STATE_COLORS.ISTIHADAH} label={t('istihadah')} icon={Info} />
            <LegendCard color={STATE_COLORS.NIFAS} label={t('nifas')} icon={Info} />
          </div>
        </section>

        {/* Stats Summary */}
        <section className="bg-emerald-50 rounded-[40px] p-8 border border-emerald-100 space-y-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className="w-12 h-12 bg-white rounded-2xl flex items-center justify-center text-emerald-600 shadow-sm">
                <Activity className="w-6 h-6" />
              </div>
              <div>
                <h4 className="text-lg font-serif font-bold text-emerald-900">{t('month_summary')}</h4>
                <p className="text-[10px] text-emerald-700/60 font-bold uppercase tracking-widest">{format(currentDate, 'MMMM yyyy')}</p>
              </div>
            </div>
            <div className="flex flex-col items-end">
              <span className="text-[10px] font-bold text-emerald-700/40 uppercase tracking-widest">{t('cycle_regularity')}</span>
              <span className="text-xl font-serif font-bold text-emerald-900">
                {cycleStats.regularity !== null ? `${cycleStats.regularity}%` : '—'}
              </span>
            </div>
          </div>
          
          <div className="grid grid-cols-2 gap-6">
            <div className="bg-white/50 p-4 rounded-3xl space-y-1">
              <span className="text-[9px] font-bold text-emerald-700/40 uppercase tracking-widest">{t('total_haid_days')}</span>
              <div className="flex flex-col">
                <div className="flex items-baseline space-x-1">
                  <p className={cn(
                    "text-2xl font-serif font-bold",
                    isHanafiPending ? "text-amber-600 text-lg" : 
                    haidDays === 0 ? "text-gray-400" : "text-emerald-900"
                  )}>
                    {isHanafiPending ? t('pending_confirmation') : haidDays.toLocaleString('en-US')}
                  </p>
                  {!isHanafiPending && <span className="text-[10px] font-bold text-emerald-700/60">{t('days')}</span>}
                </div>
                <span className={cn(
                  "text-[8px] font-bold uppercase tracking-tight",
                  isHanafiPending ? "text-amber-600/60" : "text-emerald-700/40"
                )}>
                  {isHanafiPending ? t('hanafi_72h_note') : 
                   haidDays === 0 ? (hasBloodLogged ? t('below_minimum_duration') : t('no_haid_this_month')) : 
                   ''}
                </span>
              </div>
            </div>
            <div className="bg-white/50 p-4 rounded-3xl space-y-1">
              <span className="text-[9px] font-bold text-emerald-700/40 uppercase tracking-widest">{t('total_tahara_days')}</span>
              <div className="flex items-baseline space-x-1">
                <p className="text-2xl font-serif font-bold text-emerald-900">
                  {taharaDays.toLocaleString('en-US')}
                </p>
                <span className="text-[10px] font-bold text-emerald-700/60">{t('days')}</span>
              </div>
            </div>
            <div className="bg-white/50 p-4 rounded-3xl space-y-1">
              <span className="text-[9px] font-bold text-emerald-700/40 uppercase tracking-widest">{t('avg_cycle_length')}</span>
              <div className="flex flex-col">
                <div className="flex items-baseline space-x-1">
                  <p className={cn(
                    "font-serif font-bold text-emerald-900",
                    (user?.adahLedger?.length || 0) < 2 ? "text-xs" : "text-2xl"
                  )}>
                    {cycleStats.avgCycleLength === null ? t('insufficient_data_for_calculation') : Math.round(cycleStats.avgCycleLength).toLocaleString('en-US')}
                  </p>
                  {(user?.adahLedger?.length || 0) >= 2 && <span className="text-[10px] font-bold text-emerald-700/60">{t('days')}</span>}
                </div>
              </div>
            </div>
            <div className="bg-white/50 p-4 rounded-3xl space-y-1">
              <span className="text-[9px] font-bold text-emerald-700/40 uppercase tracking-widest">{t('next_period')}</span>
              <div className="flex items-baseline space-x-1">
                <p className={cn(
                  "text-2xl font-serif font-bold",
                  cycleStats.isOverdue ? "text-amber-600" : "text-emerald-900"
                )}>
                  {cycleStats.daysUntilNext === null ? t('insufficient_data_for_calculation') : cycleStats.isOverdue ? 
                    cycleStats.overdueDays.toLocaleString('en-US') : 
                    (cycleStats.daysUntilNext === 0 ? t('today') : cycleStats.daysUntilNext.toLocaleString('en-US'))}
                </p>
                <span className={cn(
                  "text-[10px] font-bold",
                  cycleStats.isOverdue ? "text-amber-600/60" : "text-emerald-700/60"
                )}>
                  {cycleStats.daysUntilNext === null ? '' : cycleStats.isOverdue ? 
                    t('overdue_x_days', { days: cycleStats.overdueDays.toString() }) : 
                    (cycleStats.daysUntilNext === 0 ? '' : t('days_left'))}
                </span>
              </div>
            </div>
          </div>

          {/* Enhanced Insights Section */}
          <div className="grid grid-cols-1 gap-4 pt-4 border-t border-emerald-100">
            <div className="bg-white/40 p-4 rounded-3xl flex items-start space-x-4 rtl:space-x-reverse">
              <div className="w-10 h-10 bg-emerald-100 rounded-2xl flex items-center justify-center text-emerald-600 flex-shrink-0">
                <Sparkles className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h5 className="text-xs font-bold text-emerald-900">{t('fiqh_insight')}</h5>
                <p className="text-[10px] text-emerald-700/60 leading-relaxed">
                  {cycleStats.currentDay === null ? t('insufficient_data_for_calculation') : cycleStats.currentDay <= 5 ? t('haid_fiqh_reminder') : t('tahara_fiqh_reminder')}
                </p>
              </div>
            </div>
            
            <div className="bg-white/40 p-4 rounded-3xl flex items-start space-x-4 rtl:space-x-reverse">
              <div className="w-10 h-10 bg-rose-100 rounded-2xl flex items-center justify-center text-rose-600 flex-shrink-0">
                <Heart className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h5 className="text-xs font-bold text-rose-900">{t('health_tip')}</h5>
                <p className="text-[10px] text-rose-700/60 leading-relaxed">
                  {cycleStats.currentDay === null ? t('insufficient_data_for_calculation') : cycleStats.currentDay <= 5 ? t('haid_health_tip') : t('tahara_health_tip')}
                </p>
              </div>
            </div>
          </div>

          {/* Visual Progress */}
          <div className="space-y-2">
            <div className="flex justify-between text-[9px] font-bold text-emerald-700/40 uppercase tracking-widest">
              <span>{t('cycle_progress')}</span>
              <span>{cycleStats.progress === null ? '—' : `${Math.round(cycleStats.progress).toLocaleString('en-US')}%`}</span>
            </div>
            <div className="h-2 bg-emerald-100 rounded-full overflow-hidden">
              <motion.div 
                initial={{ width: 0 }}
                animate={{ width: `${cycleStats.progress ?? 0}%` }}
                className="h-full bg-emerald-500"
              />
            </div>
          </div>
        </section>
      </main>
    </div>
  );
};

const LegendCard = ({ color, label, icon: Icon }: { color: string; label: string; icon: any }) => (
  <div className="bg-white p-4 rounded-3xl border border-black/5 flex items-center space-x-3 shadow-sm">
    <div className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ backgroundColor: `${color}1A`, color }}>
      <Icon className="w-4 h-4" />
    </div>
    <span className="text-xs font-bold text-gray-700">{label}</span>
  </div>
);

import { Activity } from 'lucide-react';
