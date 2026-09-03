/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useMemo, useRef } from 'react';
import { motion, AnimatePresence, useAnimation, useMotionValue, useTransform, animate } from 'framer-motion';
import { 
  Bell, 
  User as UserIcon, 
  Plus, 
  CheckCircle2, 
  AlertCircle, 
  Moon, 
  Sun, 
  Sparkles, 
  MessageSquare,
  X,
  Heart,
  Globe,
  MapPin,
  Settings,
  AlertTriangle,
  Calendar as CalendarIcon,
  BookOpen,
  Zap,
  ChevronRight,
  Smile,
  Frown,
  Meh,
  Laugh,
  Angry,
  Clock,
  Info,
  Droplets
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import confetti from 'canvas-confetti';
import { format, addMinutes, subMinutes, isSameDay } from 'date-fns';
import * as api from '../api/index.ts';
import * as logic from '../logic/index.ts';
import { State, Madhhab, CycleEntry, STATE_COLORS, User, CycleStats, PredictionResult, OvulationResult } from '../logic/types.ts';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { useCycleData } from '../contexts/CycleContext.tsx';
import { PregnancyTracker } from './PregnancyTracker.tsx';
import { IstihadahMode } from './IstihadahMode.tsx';
import { PCOSProtocol, EndoProtocol } from './ConditionProtocols.tsx';

import { translations } from '../i18n/translations.ts';
type TranslationKey = keyof typeof translations.en;

import { notificationService } from '../services/NotificationService.ts';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// --- TYPES & CONSTANTS ---

interface TodayState {
  user: any;
  currentDay: number;
  fiqhState: State;
  daysUntilNext: number;
  prayers: any[];
  isRamadan: boolean;
  entries: CycleEntry[];
}

// --- HELPER COMPONENTS ---

const Ripple = ({ color }: { color: string }) => (
  <motion.div
    initial={{ scale: 0, opacity: 0.5 }}
    animate={{ scale: 4, opacity: 0 }}
    transition={{ duration: 0.6, ease: "easeOut" }}
    className="absolute inset-0 rounded-full pointer-events-none"
    style={{ backgroundColor: color }}
  />
);

// --- CYCLE RING (SVG Implementation) ---

const CycleRing = ({ 
  cycleStats,
  fiqhState,
  prediction,
  ovulation,
  onTap 
}: { 
  cycleStats: CycleStats;
  fiqhState: State;
  prediction: PredictionResult | null;
  ovulation: OvulationResult | null;
  onTap: () => void;
}) => {
  const { t, isRTL } = useTranslation();
  const radius = 140;
  const outerStroke = 6;
  const innerStroke = 16;
  const gap = 2; // 2px gap between segments
  
  const cycleLength = cycleStats.avgCycleLength!;
  const currentDay = cycleStats.currentDay!;
  const avgPeriodLength = cycleStats.avgPeriodLength ?? 0;
  
  // Calculate segments for outer ring
  let fertileStart = Math.floor(cycleLength / 2) - 3;
  let fertileEnd = fertileStart + 5;
  
  if (ovulation && cycleStats.lastPeriodDate) {
    const lastPeriod = new Date(cycleStats.lastPeriodDate).getTime();
    fertileStart = Math.round((ovulation.fertileWindowStart - lastPeriod) / (24 * 60 * 60 * 1000)) + 1;
    fertileEnd = Math.round((ovulation.fertileWindowEnd - lastPeriod) / (24 * 60 * 60 * 1000)) + 1;
  }

  // Ensure logical order and durations
  fertileStart = Math.max(avgPeriodLength + 1, fertileStart);
  fertileEnd = Math.min(cycleLength - 4, fertileEnd);
  const fertileDuration = fertileEnd - fertileStart + 1;

  const prePeriodDuration = 3;
  const expectedDuration = 1;
  
  const tahara1Duration = Math.max(0, fertileStart - avgPeriodLength - 1);
  const tahara2Duration = Math.max(0, (cycleLength - prePeriodDuration - expectedDuration) - fertileEnd);
  
  const segments = [
    { id: 'haid', label: t('haid'), duration: avgPeriodLength, color: '#BE123C' },
    { id: 'tahara_1', label: t('tahara'), duration: tahara1Duration, color: '#0D9488' },
    { id: 'fertile', label: t('fertile_window'), duration: fertileDuration, color: '#D97706' },
    { id: 'tahara_2', label: t('tahara'), duration: tahara2Duration, color: '#0D9488' },
    { id: 'pre_period', label: t('pre_period'), duration: prePeriodDuration, color: '#4F46E5' },
    { id: 'expected', label: t('expected_period'), duration: expectedDuration, color: '#FB7185', dashed: true },
  ].filter(s => s.duration > 0);

  // Find current phase
  let currentPhaseIndex = 0;
  let accumulatedDays = 0;
  let dayInPhase = 0;
  let startDayOfCurrentPhase = 0;
  
  for (let i = 0; i < segments.length; i++) {
    const s = segments[i];
    if (currentDay <= accumulatedDays + s.duration) {
      currentPhaseIndex = i;
      dayInPhase = currentDay - accumulatedDays;
      startDayOfCurrentPhase = accumulatedDays;
      break;
    }
    accumulatedDays += s.duration;
    if (i === segments.length - 1) {
      currentPhaseIndex = i;
      dayInPhase = currentDay - (accumulatedDays - s.duration);
      startDayOfCurrentPhase = accumulatedDays - s.duration;
    }
  }
  
  const currentPhase = segments[currentPhaseIndex];
  const nextPhase = segments[(currentPhaseIndex + 1) % segments.length];
  const daysUntilNextPhase = Math.max(1, currentPhase.duration - dayInPhase + 1);

  const normalizedRadiusOuter = radius - outerStroke / 2;
  const circumferenceOuter = normalizedRadiusOuter * 2 * Math.PI;
  
  const normalizedRadiusInner = radius - outerStroke - 12 - innerStroke / 2;
  const circumferenceInner = normalizedRadiusInner * 2 * Math.PI;

  // Inner progress arc calculation
  // The arc starts at the beginning of the current phase segment
  const phaseStartAngle = (startDayOfCurrentPhase / cycleLength) * 360 - 90;
  const phaseProgressRatio = Math.min(1, dayInPhase / currentPhase.duration);
  const phaseArcLength = (currentPhase.duration / cycleLength) * circumferenceInner;
  const currentProgressArcLength = phaseProgressRatio * phaseArcLength;
  const currentAngle = phaseStartAngle + (phaseProgressRatio * (currentPhase.duration / cycleLength) * 360);

  return (
    <div className="flex flex-col items-center space-y-10">
      <div className="relative flex items-center justify-center cursor-pointer group" onClick={onTap}>
        {/* Outer Glow/Shadow */}
        <div className="absolute w-[300px] h-[300px] rounded-full bg-white shadow-[0_20px_50px_rgba(0,0,0,0.05)]" />
        
        <svg height={radius * 2} width={radius * 2} className="relative z-10 overflow-visible">
          {/* Outer Thin Ring Segments (Map) */}
          <g transform={`rotate(-90 ${radius} ${radius})`}>
            {(() => {
              let cumulativeOffset = 0;
              return segments.map((segment, idx) => {
                const arcLength = (segment.duration / cycleLength) * circumferenceOuter;
                const gapSize = (gap / circumferenceOuter) * circumferenceOuter;
                const visibleArcLength = arcLength - gapSize;
                const offset = cumulativeOffset;
                cumulativeOffset += arcLength;
                
                const isActive = idx === currentPhaseIndex;
                
                return (
                  <circle
                    key={idx}
                    stroke={segment.color}
                    fill="transparent"
                    strokeWidth={outerStroke}
                    strokeDasharray={segment.dashed ? "4,2" : `${visibleArcLength} ${circumferenceOuter - visibleArcLength}`}
                    strokeDashoffset={-offset}
                    r={normalizedRadiusOuter}
                    cx={radius}
                    cy={radius}
                    className={cn(
                      "transition-opacity duration-500",
                      isActive ? "opacity-100" : "opacity-30"
                    )}
                  />
                );
              });
            })()}
          </g>

          {/* Inner Ring Track (Light Gray) */}
          <circle
            stroke="#F5F5F5"
            fill="transparent"
            strokeWidth={innerStroke}
            r={normalizedRadiusInner}
            cx={radius}
            cy={radius}
            transform={`rotate(-90 ${radius} ${radius})`}
          />

          {/* Inner Thick Progress Ring (Current Phase Only) */}
          <motion.circle
            stroke={currentPhase.color}
            fill="transparent"
            strokeWidth={innerStroke}
            strokeDasharray={`${currentProgressArcLength} ${circumferenceInner}`}
            strokeDashoffset={-(startDayOfCurrentPhase / cycleLength) * circumferenceInner}
            strokeLinecap="round"
            initial={{ strokeDasharray: `0 ${circumferenceInner}` }}
            animate={{ strokeDasharray: `${currentProgressArcLength} ${circumferenceInner}` }}
            transition={{ duration: 1, ease: 'easeOut' }}
            r={normalizedRadiusInner}
            cx={radius}
            cy={radius}
            transform={`rotate(-90 ${radius} ${radius})`}
          />

          {/* Animated "You Are Here" Dot at leading edge */}
          <motion.g
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.5 }}
          >
            {/* Pulse effect */}
            <motion.circle
              fill={currentPhase.color}
              r={10}
              cx={radius + normalizedRadiusInner * Math.cos((currentAngle * Math.PI) / 180)}
              cy={radius + normalizedRadiusInner * Math.sin((currentAngle * Math.PI) / 180)}
              animate={{ 
                scale: [1, 1.5, 1],
                opacity: [0.4, 0.1, 0.4]
              }}
              transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
            />
            <circle
              fill="white"
              stroke={currentPhase.color}
              strokeWidth={3}
              r={7}
              cx={radius + normalizedRadiusInner * Math.cos((currentAngle * Math.PI) / 180)}
              cy={radius + normalizedRadiusInner * Math.sin((currentAngle * Math.PI) / 180)}
              className="shadow-md"
            />
          </motion.g>
        </svg>

        {/* Center Content */}
        <div className="absolute flex flex-col items-center justify-center text-center z-20 w-full px-10">
          <motion.div
            initial={{ y: 10, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            className="flex flex-col items-center"
          >
            <span className="text-[11px] font-bold text-gray-400 uppercase tracking-[0.2em] mb-2">
              {isRTL ? `${dayInPhase.toLocaleString('ar-SA-u-nu-latn')} يوم من ${currentPhase.duration.toLocaleString('ar-SA-u-nu-latn')}` : `Day ${dayInPhase} of ${currentPhase.duration}`}
            </span>
            <span 
              className="text-[32px] font-serif font-bold leading-tight mb-2"
              style={{ color: currentPhase.color }} 
            >
              {currentPhase.label}
            </span>
            <div className="h-[1px] w-8 bg-gray-200 mb-3" />
            <span className="text-[11px] font-medium text-gray-400 flex items-center space-x-1 rtl:space-x-reverse">
              <span className="opacity-50">←</span>
              <span className="font-bold text-gray-600">
                {nextPhase.label} {isRTL ? `خلال ${daysUntilNextPhase.toLocaleString('ar-SA-u-nu-latn')} يوماً` : `in ${daysUntilNextPhase} days`}
              </span>
            </span>
          </motion.div>
        </div>
      </div>

      {/* Phase Timeline Strip */}
      <PhaseTimeline 
        segments={segments} 
        currentPhaseIndex={currentPhaseIndex} 
        currentDay={currentDay}
      />
    </div>
  );
};

const PhaseTimeline = ({ 
  segments, 
  currentPhaseIndex,
  currentDay
}: { 
  segments: any[]; 
  currentPhaseIndex: number; 
  currentDay: number;
}) => {
  const { t, isRTL } = useTranslation();
  const totalDuration = segments.reduce((acc, s) => acc + s.duration, 0);
  
  return (
    <div className="w-full max-w-[320px] space-y-4">
      <div className="relative">
        {/* Triangle Pointer */}
        {(() => {
          const progress = (currentDay / totalDuration) * 100;
          return (
            <div 
              className="absolute top-[-20px] transform -translate-x-1/2 flex flex-col items-center z-10"
              style={{ [isRTL ? 'right' : 'left']: `${progress}%` }}
            >
              <span className="text-[9px] font-black text-rose-500 mb-0.5 whitespace-nowrap bg-white px-1 rounded shadow-sm border border-rose-100">
                {isRTL ? 'أنتِ هنا' : 'You are here'}
              </span>
              <div className="w-0 h-0 border-l-[4px] border-l-transparent border-r-[4px] border-r-transparent border-t-[6px] border-t-rose-500" />
            </div>
          );
        })()}

        <div className="h-2 flex rounded-full overflow-hidden bg-gray-100 shadow-inner">
          {segments.map((segment, idx) => (
            <div 
              key={idx}
              style={{ 
                width: `${(segment.duration / totalDuration) * 100}%`,
                backgroundColor: segment.color,
                opacity: idx === currentPhaseIndex ? 1 : 0.3
              }}
              className="h-full transition-opacity duration-500"
            />
          ))}
        </div>
      </div>
      
      <div className="flex justify-between px-1">
        {segments.map((segment, idx) => (
          <div 
            key={idx} 
            className="flex flex-col items-center"
            style={{ width: `${(segment.duration / totalDuration) * 100}%` }}
          >
            <span className={cn(
              "text-[8px] font-bold truncate w-full text-center",
              idx === currentPhaseIndex ? "text-gray-900" : "text-gray-400"
            )}>
              {segment.label}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};

// --- FIQH STATE BANNER ---

const FiqhStateBanner = ({ state, madhhab, currentDay, cycleLength, haidDuration }: { state: State; madhhab: Madhhab; currentDay: number; cycleLength: number; haidDuration: number }) => {
  const { t, isRTL } = useTranslation();
  const locale = isRTL ? 'ar-SA' : 'en-US';
  
  const isExpectedPeriod = state === 'TAHARA' && (currentDay <= haidDuration || currentDay > cycleLength);
  
  const config = {
    HAID: {
      color: STATE_COLORS.HAID,
      label: t('haid'),
      message: t('salah_lifted'),
      sub: t('based_on_madhhab', { madhhab }).replace('{madhhab}', madhhab)
    },
    TAHARA: {
      color: STATE_COLORS.TAHARA,
      label: isExpectedPeriod ? t('expected_period_day_x', { x: (currentDay > cycleLength ? currentDay - cycleLength : currentDay).toLocaleString('en-US') }) : t('tahara'),
      message: isExpectedPeriod ? t('expected_period_desc') : t('salah_obligatory'),
      sub: isExpectedPeriod ? t('log_blood_to_start') : ''
    },
    NIFAS: {
      color: STATE_COLORS.NIFAS,
      label: t('nifas'),
      message: t('nifas_desc'),
      sub: t('nifas_max')
    },
    ISTIHADAH: {
      color: STATE_COLORS.ISTIHADAH,
      label: t('istihadah'),
      message: t('log_details_fiqh'),
      sub: ''
    }
  }[state];

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      className="w-full p-6 rounded-3xl border-l-[4px] space-y-2 cursor-pointer relative overflow-hidden"
      style={{ 
        borderColor: config.color,
        backgroundColor: `${config.color}1A` // 10% opacity
      }}
    >
      <div className="flex items-center justify-between relative z-10">
        <span className="font-bold uppercase tracking-widest text-[10px]" style={{ color: config.color }}>{config.label}</span>
        <ChevronRight className="w-4 h-4 opacity-30" />
      </div>
      <p className="text-sm font-medium leading-relaxed text-gray-800 relative z-10">{config.message}</p>
      {config.sub && <p className="text-[10px] opacity-50 font-bold uppercase tracking-wider relative z-10">{config.sub}</p>}
      
      {state === 'ISTIHADAH' && (
        <button className="mt-3 px-4 py-2 bg-rose-400 text-white text-[10px] font-bold rounded-full relative z-10">
          {t('log_today_blood')}
        </button>
      )}
    </motion.div>
  );
};

// --- LOG BOTTOM SHEET ---

const LogBottomSheet = ({ isOpen, onClose, madhhab, onSave, currentState, defaultIntensity = 'none' }: { isOpen: boolean; onClose: () => void; madhhab: Madhhab; onSave: (data: any) => void; currentState: State; defaultIntensity?: string }) => {
  const { t, isRTL } = useTranslation();
  const [intensity, setIntensity] = useState(defaultIntensity);

  useEffect(() => {
    setIntensity(defaultIntensity);
  }, [defaultIntensity, isOpen]);
  const [color, setColor] = useState('red');
  const [thickness, setThickness] = useState('normal');
  const [kursuf, setKursuf] = useState(false);
  const [internal, setInternal] = useState(false);
  const [selectedSymptoms, setSelectedSymptoms] = useState<string[]>([]);
  const [mood, setMood] = useState(2);
  const [feeling, setFeeling] = useState('');
  const [notes, setNotes] = useState('');

  const symptoms = [
    t('cramps'), t('bloating'), t('headache'), t('backache'),
    t('mood_changes'), t('fatigue'), t('tender_breasts'),
    t('acne'), t('nausea'), t('insomnia'), t('spotting'), t('clots')
  ];

  const feelingTags = [
    t('feeling_anxious'), t('feeling_peaceful'), t('feeling_energetic'),
    t('feeling_tired'), t('feeling_emotional'), t('feeling_calm'),
    t('feeling_stressed'), t('feeling_happy')
  ];

  const moods = [
    { Icon: Frown, label: t('mood_sad') },
    { Icon: Meh, label: t('mood_neutral') },
    { Icon: Smile, label: t('mood_happy') },
    { Icon: Laugh, label: t('mood_joyful') },
    { Icon: Angry, label: t('mood_angry') }
  ];

  const handleSave = () => {
    onSave({
      intensity,
      color,
      thickness,
      kursuf,
      internal,
      symptoms: selectedSymptoms,
      mood,
      feeling,
      notes,
      timestamp: new Date().toISOString()
    });
    confetti({ particleCount: 100, spread: 70, origin: { y: 0.8 } });
    onClose();
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/40 z-[100] backdrop-blur-sm"
          />
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 18, stiffness: 200 }}
            className="fixed bottom-0 left-0 right-0 bg-[#FDFCFB] rounded-t-[40px] z-[101] max-h-[92vh] overflow-y-auto p-8 space-y-8 shadow-2xl"
          >
            <div className="w-12 h-1.5 bg-gray-200 rounded-full mx-auto mb-2" />
            <div className="flex items-center justify-between">
              <h3 className="text-xl font-serif font-bold text-rose-800">{t('log_today')}</h3>
              <button onClick={onClose} className="p-2 bg-gray-100 rounded-full"><X className="w-5 h-5 text-gray-400" /></button>
            </div>
            
            {/* Intensity */}
            <section className="space-y-4">
              <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('flow_intensity')}</h4>
              <div className="flex justify-between">
                {['none', 'spotting', 'light', 'medium', 'heavy'].map(lvl => (
                  <motion.button
                    key={lvl}
                    whileTap={{ scale: 0.9 }}
                    onClick={() => setIntensity(lvl)}
                    className={cn(
                      "flex flex-col items-center space-y-1",
                      intensity === lvl ? "text-rose-400" : "text-gray-300"
                    )}
                  >
                    <div className={cn(
                      "w-12 h-12 rounded-2xl border-2 flex items-center justify-center transition-all",
                      intensity === lvl ? "border-rose-300 bg-rose-50" : "border-black/5"
                    )}>
                      <div className={cn("w-6 h-6 rounded-full", lvl === 'none' ? 'border-2 border-dashed border-gray-200' : 'bg-current')} style={{ opacity: intensity === lvl ? 1 : 0.2 }} />
                    </div>
                    <span className="text-[8px] font-bold uppercase">{lvl === 'none' && currentState === 'HAID' ? t('period_end') : t(lvl as TranslationKey)}</span>
                  </motion.button>
                ))}
              </div>
            </section>

            {/* Color */}
            <section className="space-y-4">
              <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('blood_color')}</h4>
              <div className="flex space-x-4">
                {[
                  { id: 'red', hex: '#F43F5E' },
                  { id: 'dark', hex: '#9F1239' },
                  { id: 'brown', hex: '#78350F' },
                  { id: 'pink', hex: '#FB7185' },
                  { id: 'other', hex: '#D1D5DB' }
                ].map((c) => (
                  <div key={c.id} className="flex flex-col items-center space-y-1">
                    <motion.button
                      animate={{ scale: color === c.id ? 1.25 : 1 }}
                      onClick={() => setColor(c.id)}
                      className={cn(
                        "w-8 h-8 rounded-full border-2 shadow-sm transition-all",
                        color === c.id ? "border-rose-300" : "border-white"
                      )}
                      style={{ backgroundColor: c.hex }}
                    />
                    <span className="text-[8px] font-bold text-gray-400 uppercase">{t(c.id as TranslationKey)}</span>
                  </div>
                ))}
              </div>
            </section>

            {/* Kursuf (Hanafi) */}
            {madhhab === 'HANAFI' && (
              <section className="space-y-4 p-6 bg-rose-50 rounded-3xl border border-rose-100">
                <div className="flex items-center justify-between">
                  <div>
                    <h4 className="text-sm font-bold text-rose-800">{t('internal_tracking')}</h4>
                    <p className="text-[10px] text-rose-400/60">{t('internal_barrier_q')}</p>
                  </div>
                  <button 
                    onClick={() => setKursuf(!kursuf)}
                    className={cn("w-12 h-6 rounded-full relative transition-all", kursuf ? "bg-rose-400" : "bg-rose-100")}
                  >
                    <motion.div animate={{ x: kursuf ? 24 : 4 }} className="absolute top-1 w-4 h-4 bg-white rounded-full shadow-sm" />
                  </button>
                </div>
                <AnimatePresence>
                  {kursuf && (
                    <motion.div 
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      className="space-y-3 overflow-hidden pt-2"
                    >
                      <p className="text-[10px] font-bold text-rose-800 uppercase">{t('discharge_location')}</p>
                      <div className="flex space-x-2">
                        {[t('internal'), t('external_only')].map(opt => (
                          <button
                            key={opt}
                            onClick={() => setInternal(opt === t('internal'))}
                            className={cn(
                              "flex-1 py-3 rounded-xl border-2 text-[10px] font-bold transition-all",
                              (opt === t('internal') ? internal : !internal) ? "border-rose-300 bg-white text-rose-800" : "border-rose-100 bg-rose-50/50 text-rose-200"
                            )}
                          >
                            {opt}
                          </button>
                        ))}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </section>
            )}

            {/* Symptoms */}
            <section className="space-y-4">
              <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('symptoms')}</h4>
              <div className="grid grid-cols-3 gap-2">
                {symptoms.map(s => (
                  <motion.button
                    key={s}
                    whileTap={{ scale: 0.95 }}
                    onClick={() => setSelectedSymptoms(prev => prev.includes(s) ? prev.filter(x => x !== s) : [...prev, s])}
                    className={cn(
                      "py-3 px-2 rounded-xl border-2 text-[10px] font-bold transition-all",
                      selectedSymptoms.includes(s) ? "border-rose-300 bg-rose-400 text-white shadow-md" : "border-black/5 text-gray-500"
                    )}
                  >
                    {s}
                  </motion.button>
                ))}
              </div>
            </section>

            {/* Mood */}
            <section className="space-y-6">
              <div className="flex items-center justify-between">
                <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('mood')}</h4>
                <span className="text-[10px] font-bold text-rose-400 uppercase tracking-widest">{moods[mood].label}</span>
              </div>
              <div className="flex justify-between px-2">
                {moods.map(({ Icon }, i) => (
                  <motion.button
                    key={i}
                    animate={{ 
                      scale: mood === i ? 1.4 : 1,
                      color: mood === i ? '#F43F5E' : '#D1D5DB'
                    }}
                    onClick={() => setMood(i)}
                    className={cn(
                      "p-3 rounded-full transition-all",
                      mood === i ? "bg-rose-50 shadow-inner" : "bg-transparent"
                    )}
                  >
                    <Icon className="w-8 h-8" />
                  </motion.button>
                ))}
              </div>

              {/* Expressive Feeling Input */}
              <div className="space-y-4 pt-2">
                <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('feeling')}</h4>
                <div className="flex flex-wrap gap-2">
                  {feelingTags.map(tag => (
                    <motion.button
                      key={tag}
                      whileTap={{ scale: 0.95 }}
                      onClick={() => setFeeling(prev => prev.includes(tag) ? prev.replace(tag, '').trim() : `${prev} ${tag}`.trim())}
                      className={cn(
                        "px-4 py-2 rounded-full border text-[10px] font-bold transition-all",
                        feeling.includes(tag) ? "border-rose-300 bg-rose-400 text-white shadow-md" : "border-black/5 text-gray-500 bg-white"
                      )}
                    >
                      {tag}
                    </motion.button>
                  ))}
                </div>
                <input 
                  type="text"
                  value={feeling}
                  onChange={(e) => setFeeling(e.target.value)}
                  placeholder={t('mood_placeholder')}
                  className="w-full p-4 rounded-2xl border-2 border-black/5 bg-white text-sm focus:border-rose-300 outline-none transition-all"
                />
              </div>
            </section>

            {/* Notes */}
            <section className="space-y-4">
              <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('notes')}</h4>
              <textarea 
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder={t('how_feeling')}
                className="w-full p-4 rounded-2xl border-2 border-black/5 bg-white text-sm focus:border-rose-300 outline-none transition-all min-h-[100px]"
              />
            </section>

            <button 
              onClick={handleSave}
              className="w-full py-5 bg-rose-400 text-white rounded-2xl font-bold shadow-xl shadow-rose-100 flex items-center justify-center space-x-2"
            >
              <CheckCircle2 className="w-5 h-5" />
              <span>{t('save_log')}</span>
            </button>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

// --- NO CITY PROMPT CARD ---

const NoCityPromptCard = ({ onAction }: { onAction: () => void }) => {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="w-full p-8 rounded-[32px] bg-white border border-rose-100 shadow-sm flex flex-col items-center text-center space-y-4"
    >
      <div className="w-16 h-16 bg-rose-50 rounded-full flex items-center justify-center">
        <MapPin className="w-8 h-8 text-rose-400" />
      </div>
      <div className="space-y-1">
        <h3 className="text-lg font-bold text-gray-800">حددي مدينتك لعرض أوقات الصلاة</h3>
        <p className="text-sm text-gray-400">نحتاج لمعرفة موقعك لحساب مواقيت الصلاة بدقة</p>
      </div>
      <button
        onClick={onAction}
        className="px-8 py-3 bg-rose-400 text-white rounded-full text-sm font-bold shadow-lg shadow-rose-100 active:scale-95 transition-transform"
      >
        اختاري مدينتك
      </button>
    </motion.div>
  );
};

// --- PRAYER STATUS WIDGET ---

const PrayerStatusWidget = ({ state, onOpenSettings }: { state: State; onOpenSettings: () => void }) => {
  const { t, isRTL } = useTranslation();
  const { 
    user, 
    prayerTimes, 
    prayers: prayerLogs, 
    entries, 
    prayerTimesLoading, 
    prayerTimesError,
    updatePrayerTimes 
  } = useCycleData();

  const isHaidOrNifas = state === 'HAID' || state === 'NIFAS';

  // Find the latest HAID start in the current cycle
  const latestHaidStart = useMemo(() => {
    const haidEntries = entries
      .filter(e => e.fiqh_state === 'HAID')
      .sort((a, b) => b.time_logged.localeCompare(a.time_logged));
    return haidEntries.length > 0 ? new Date(haidEntries[0].time_logged).getTime() : null;
  }, [entries]);

  const prayers = useMemo(() => {
    if (prayerTimes.length === 0) return [];

    const arabicNames: Record<string, string> = {
      fajr: 'الفجر',
      dhuhr: 'الظهر',
      asr: 'العصر',
      maghrib: 'المغرب',
      isha: 'العشاء'
    };

    return prayerTimes.map(pt => {
      const log = prayerLogs.find(l => l.prayer_name.toLowerCase() === pt.name.toLowerCase());
      const isPrayed = log?.status === 'prayed';
      
      let status: 'prayed' | 'qadha_required' | 'lifted' | 'missed' | 'upcoming' = 'upcoming';
      
      if (isPrayed) {
        status = 'prayed';
      } else if (state === 'HAID' && latestHaidStart) {
        if (pt.adhanTime < latestHaidStart) {
          status = 'qadha_required';
        } else {
          status = 'lifted';
        }
      } else if (pt.adhanTime < Date.now()) {
        status = 'missed';
      }

      const timeFormatted = new Date(pt.adhanTime).toLocaleTimeString(isRTL ? 'ar-SA' : 'en-US', { 
        hour: '2-digit', 
        minute: '2-digit', 
        hour12: true 
      });

      return {
        id: pt.name,
        name: arabicNames[pt.name.toLowerCase()] || pt.name,
        time: timeFormatted,
        status,
        icon: pt.name.toLowerCase() === 'fajr' ? Moon : Sun
      };
    });
  }, [prayerTimes, prayerLogs, state, latestHaidStart]);

  if (!user?.prayerCity && !(user?.prayerLat && user?.prayerLon)) {
    return <NoCityPromptCard onAction={onOpenSettings} />;
  }

  if (prayerTimesLoading) {
    return (
      <div className="w-full p-6 rounded-[32px] bg-white shadow-sm space-y-6">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-serif font-bold text-rose-800">أوقات الصلاة</h3>
          <span className="text-xs text-gray-300 animate-pulse">جاري التحميل...</span>
        </div>
        <div className="space-y-4">
          {[1, 2, 3, 4, 5].map(i => (
            <div key={i} className="flex items-center justify-between animate-pulse">
              <div className="flex items-center space-x-3 rtl:space-x-reverse">
                <div className="w-8 h-8 bg-gray-100 rounded-full" />
                <div className="w-16 h-4 bg-gray-100 rounded-md" />
              </div>
              <div className="w-12 h-4 bg-gray-100 rounded-md" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (prayerTimesError) {
    return (
      <div className="w-full p-8 rounded-[32px] bg-white border border-rose-100 shadow-sm flex flex-col items-center text-center space-y-4">
        <AlertCircle className="w-10 h-10 text-rose-400" />
        <p className="text-sm text-gray-600">تعذّر تحميل أوقات الصلاة لـ {user.prayerCityAr || user.prayerCity}</p>
        <button 
          onClick={() => updatePrayerTimes(true)}
          className="text-xs font-bold text-rose-400 uppercase tracking-widest"
        >
          إعادة المحاولة
        </button>
      </div>
    );
  }

  if (isHaidOrNifas) {
    return (
      <motion.div 
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full p-6 rounded-[32px] bg-white shadow-xl shadow-black/5 border border-black/5 flex flex-col items-center text-center space-y-4"
      >
        <div className="w-12 h-12 bg-rose-50 rounded-full flex items-center justify-center text-rose-500">
          <Moon className="w-6 h-6" />
        </div>
        <div className="space-y-1">
          <h3 className="text-lg font-serif font-bold text-emerald-900">{t('salah_lifted')}</h3>
          <p className="text-xs text-gray-500 leading-relaxed px-4">
            {t('salah_lifted_desc' as any)}
          </p>
        </div>
        <div className="flex items-center space-x-2 text-[10px] font-bold text-rose-400 uppercase tracking-widest">
          <Sparkles className="w-3 h-3" />
          <span>{t('focus_on_zikr' as any)}</span>
        </div>
      </motion.div>
    );
  }

  return (
    <motion.div 
      layout
      className="w-full p-6 rounded-[32px] bg-white shadow-sm space-y-6"
    >
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h3 className="text-lg font-serif font-bold text-rose-800">{t('prayer_times')}</h3>
          <p className="text-[10px] text-gray-400 leading-relaxed max-w-[200px]">
            {t('prayer_times_reason')}
          </p>
        </div>
        <button 
          onClick={onOpenSettings}
          className="text-xs font-medium text-gray-400 flex items-center space-x-1 rtl:space-x-reverse"
        >
          <span>{user.prayerCityAr || user.prayerCity}</span>
          <ChevronRight className="w-3 h-3" />
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3">
        {prayers.map((p) => (
          <div key={p.id} className="flex flex-col p-4 rounded-2xl bg-gray-50/50 border border-black/[0.02] space-y-3 group">
            <div className="flex items-center justify-between">
              <div className={cn(
                "w-8 h-8 rounded-full flex items-center justify-center transition-colors",
                p.status === 'prayed' ? "bg-emerald-100 text-emerald-600" : 
                p.status === 'lifted' ? "bg-rose-100 text-rose-500" :
                p.status === 'missed' ? "bg-amber-100 text-amber-600" :
                "bg-white text-gray-400 shadow-sm"
              )}>
                <p.icon className="w-4 h-4" />
              </div>
              <span className={cn(
                "text-[8px] font-bold uppercase tracking-wider px-2 py-1 rounded-md",
                p.status === 'prayed' ? "bg-emerald-500 text-white" :
                p.status === 'lifted' ? "bg-rose-500 text-white" :
                p.status === 'qadha_required' ? "bg-amber-500 text-white" :
                p.status === 'missed' ? "bg-gray-200 text-gray-500" :
                "bg-emerald-100 text-emerald-700" // Upcoming
              )}>
                {p.status === 'prayed' ? t('prayed' as any) || 'صُليت' : 
                 p.status === 'lifted' ? t('lifted' as any) || 'مرفوعة' : 
                 p.status === 'qadha_required' ? t('qadha_after_ghusl' as any) || 'قضاء بعد الغسل' :
                 p.status === 'missed' ? t('prayer_status_ended') : 
                 t('prayer_status_upcoming')}
              </span>
            </div>

            <div>
              <p className="text-xs font-bold text-gray-800">{p.name}</p>
              <p className="text-[10px] text-gray-400 font-medium">{p.time}</p>
            </div>
          </div>
        ))}
      </div>
    </motion.div>
  );
};

// --- WORSHIP WITHOUT SALAH WIDGET ---

const WorshipWithoutSalah = () => {
  const { t } = useTranslation();
  const [counts, setCounts] = useState({ Zikir: 0, Dua: 0, Salawat: 0, Istighfar: 0 });
  const [ripples, setRipples] = useState<{ id: number, key: string }[]>([]);

  const increment = (key: keyof typeof counts) => {
    const newVal = counts[key] + 1;
    setCounts(prev => ({ ...prev, [key]: newVal }));
    setRipples(prev => [...prev, { id: Date.now(), key }]);
    
    if (newVal === 33) {
      // Ripple logic handled by state
    }
    if (newVal === 99) {
      confetti({ particleCount: 100, spread: 70, origin: { y: 0.6 } });
    }
  };

  const suggestions = [
    { text: t('read_surah_maryam'), icon: BookOpen },
    { text: t('dua_ease_pain'), icon: Heart },
    { text: t('try_gentle_stretching'), icon: Zap },
    { text: t('listen_to_podcast'), icon: BookOpen },
    { text: t('istighfar'), icon: Sparkles },
    { text: t('drink_ginger_tea'), icon: Sun },
    { text: t('salawat'), icon: Moon }
  ];

  return (
    <motion.div 
      layout
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.95 }}
      className="w-full space-y-6"
    >
      <div className="grid grid-cols-4 gap-2">
        {Object.entries(counts).map(([label, val]) => (
          <motion.button
            key={label}
            whileTap={{ scale: 0.92 }}
            onClick={() => increment(label as any)}
            className="bg-white rounded-2xl p-4 shadow-lg shadow-black/5 border border-black/5 flex flex-col items-center space-y-1 relative overflow-hidden"
          >
            <AnimatePresence>
              {ripples.filter(r => r.key === label).map(r => (
                <Ripple key={r.id} color="#F43F5E22" />
              ))}
            </AnimatePresence>
            <motion.span 
              key={val}
              initial={{ scale: 1.5, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className={cn("text-xl font-serif font-bold", (val as number) >= 99 ? "text-amber-500" : "text-rose-400")}
            >
              {val}
            </motion.span>
            <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">{t(label.toLowerCase() as TranslationKey)}</span>
          </motion.button>
        ))}
      </div>

      <div className="flex overflow-x-auto space-x-3 pb-2 no-scrollbar">
        {suggestions.map((s, i) => (
          <motion.div 
            key={i} 
            whileTap={{ scale: 0.98 }}
            className="flex-shrink-0 bg-rose-50 p-4 rounded-2xl border border-rose-100 max-w-[180px] flex flex-col space-y-2 cursor-pointer"
          >
            <s.icon className="w-4 h-4 text-rose-400" />
            <p className="text-[10px] font-medium text-rose-800 leading-relaxed">{s.text}</p>
          </motion.div>
        ))}
      </div>
    </motion.div>
  );
};

// --- DAILY INSIGHTS ---

const DreamInterpreterWidget = ({ onClick }: { onClick: () => void }) => {
  const { t, isRTL } = useTranslation();
  return (
    <motion.section 
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="p-6 bg-rose-50 rounded-[32px] border border-rose-100 space-y-4 cursor-pointer relative overflow-hidden group"
    >
      <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
        <Moon className="w-24 h-24 text-rose-900" />
      </div>
      <div className="flex items-center justify-between relative z-10">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-white rounded-full flex items-center justify-center text-rose-600 shadow-sm">
            <Sparkles className="w-5 h-5" />
          </div>
          <h3 className="font-bold text-rose-900">{t('dream_interpretation')}</h3>
        </div>
        <ChevronRight className={cn("w-5 h-5 text-rose-400", isRTL && "rotate-180")} />
      </div>
      <p className="text-xs text-rose-800/60 leading-relaxed relative z-10">
        {t('dream_interpreter_desc')}
      </p>
    </motion.section>
  );
};

// --- MAIN TODAY SCREEN ---

export const Today = ({ 
  onOpenAI, 
  onOpenDreamInterpreter,
  onOpenSettings
}: { 
  onOpenAI: () => void; 
  onOpenDreamInterpreter: () => void;
  onOpenSettings: () => void;
}) => {
  const { t, isRTL } = useTranslation();
  const { user, fiqhState: contextState, currentDay, cycleStats, prediction, ovulation, entries, loading: dataLoading, refresh } = useCycleData();
  const [localFiqhState, setLocalFiqhState] = useState<State | null>(null);
  const state = localFiqhState || contextState;

  useEffect(() => {
    if (contextState === localFiqhState) {
      setLocalFiqhState(null);
    }
  }, [contextState, localFiqhState]);
  const [isLogOpen, setIsLogOpen] = useState(false);
  const [defaultIntensity, setDefaultIntensity] = useState('none');
  const [showBloom, setShowBloom] = useState(false);
  const [bloomMessage, setBloomMessage] = useState('');
  const [isIstihadahMode, setIsIstihadahMode] = useState(false);

  useEffect(() => {
    // Sync local state if needed
  }, [state, currentDay]);

  const cycleLength = cycleStats.avgCycleLength;
  const haidDuration = cycleStats.avgPeriodLength;

  const handleSaveLog = async (logData: any) => {
    try {
      const newState = (logData.intensity === 'none' ? 'TAHARA' : 'HAID') as State;
      
      const entry: Partial<api.DBCycleEntry> = {
        date: format(new Date(), 'yyyy-MM-dd'),
        time_logged: logData.timestamp,
        fiqh_state: newState,
        flow_intensity: logData.intensity as any,
        blood_color: logData.color as any,
        blood_thickness: logData.thickness as any,
        kursuf_used: logData.kursuf,
        discharge_internal: logData.internal,
        notes: logData.notes,
        is_predicted: false
      };

      // Optimistic update
      // No longer needed with context refresh

      await api.logCycleEntry(entry);
      
      // Nuclear Option: Set local state immediately
      setLocalFiqhState(newState);
      
      await refresh();
      
      // Update state and trigger animations
      if (newState !== state) {
        if (newState === 'HAID') {
          setBloomMessage(t('ease_and_rest'));
          setShowBloom(true);
          setTimeout(() => setShowBloom(false), 2500);
        } else if (newState === 'TAHARA') {
          setBloomMessage(t('welcome_back_tahara'));
          setShowBloom(true);
          setTimeout(() => setShowBloom(false), 2500);
        }
      }
    } catch (err) {
      console.error("Failed to save log", err);
    }
  };

  const isPregnant = user?.pregnant || false;
  const hasPCOS = user?.conditions?.includes('PCOS');
  const hasEndo = user?.conditions?.includes('Endometriosis');
  const hasCyclePattern = cycleStats.currentDay !== null && cycleStats.avgCycleLength !== null;

  if (dataLoading) return (
    <div className="fixed inset-0 bg-[#FDFCFB] flex items-center justify-center">
      <motion.div animate={{ rotate: 360 }} transition={{ repeat: Infinity, duration: 1, ease: 'linear' }} className="w-8 h-8 border-4 border-emerald-500 border-t-transparent rounded-full" />
    </div>
  );

  return (
    <div className="min-h-screen bg-[#FDFCFB] pb-32 relative overflow-x-hidden">
      {/* State Change Bloom */}
      <AnimatePresence>
        {showBloom && (
          <motion.div 
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 2, opacity: 1 }}
            exit={{ scale: 3, opacity: 0 }}
            transition={{ duration: 0.8, ease: "easeOut" }}
            className="fixed inset-0 z-[300] flex items-center justify-center pointer-events-none"
          >
            <div className="w-64 h-64 rounded-full blur-3xl" style={{ backgroundColor: `${STATE_COLORS[state]}44` }} />
            <motion.p 
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              className="absolute text-xl font-serif font-bold text-emerald-900 text-center px-8"
            >
              {bloomMessage}
            </motion.p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Top Bar */}
      <header className="p-6 flex items-center justify-between sticky top-0 bg-[#FDFCFB]/80 backdrop-blur-md z-50">
        <div className="space-y-0.5">
          <h1 className="text-xl font-serif font-bold text-emerald-900">Niswah</h1>
          <p className="text-[10px] text-emerald-700/60 font-bold tracking-widest uppercase">{t('ahlan')}, {user?.anonymous_mode ? t('sister') : (user?.display_name || t('sister'))}</p>
        </div>
        <div className="flex items-center space-x-4">
          <div className="relative cursor-pointer">
            <Bell className="w-6 h-6 text-emerald-900" />
            <motion.div 
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              className="absolute -top-1 -right-1 w-4 h-4 bg-rose-500 rounded-full border-2 border-[#FDFCFB] flex items-center justify-center"
            >
              <span className="text-[8px] text-white font-bold">{(3).toLocaleString('en-US')}</span>
            </motion.div>
          </div>
          <div className="w-10 h-10 bg-emerald-100 rounded-full flex items-center justify-center border-2 border-white shadow-sm overflow-hidden">
            <span className="text-emerald-700 font-bold text-sm uppercase">{user?.display_name?.substring(0, 2) || 'AN'}</span>
          </div>
        </div>
      </header>

      <main className="px-6 space-y-8">
          {/* Main Cycle Ring or Pregnancy Tracker */}
          <section className="flex flex-col items-center py-6 space-y-6">
            {isPregnant ? (
              <PregnancyTracker 
                currentWeek={12} // Mock
                onLogBirth={() => {
                  // Handle birth logging logic
                }} 
              />
            ) : !hasCyclePattern ? (
              <div className="w-full max-w-sm rounded-[32px] border border-black/5 bg-white p-8 text-center shadow-sm space-y-4">
                <CalendarIcon className="w-8 h-8 mx-auto text-emerald-600" />
                <h2 className="font-serif text-xl font-bold text-emerald-900">
                  {isRTL ? 'سجّلي دورتكِ لمعرفة يومكِ' : 'Log your cycle to see your day'}
                </h2>
                <p className="text-sm text-gray-500">
                  {isRTL
                    ? 'نحتاج إلى تسجيل بدايتَي حيض لحساب نمط دورتكِ الشخصي.'
                    : 'Two logged Haid starts are needed to calculate your personal cycle pattern.'}
                </p>
                <button
                  onClick={() => {
                    setDefaultIntensity('medium');
                    setIsLogOpen(true);
                  }}
                  className="w-full rounded-2xl bg-rose-600 py-3 text-sm font-bold text-white"
                >
                  {isRTL ? 'تسجيل الدورة' : 'Log cycle'}
                </button>
              </div>
            ) : (
              <>
                <CycleRing 
                  cycleStats={cycleStats}
                  fiqhState={state}
                  prediction={prediction}
                  ovulation={ovulation}
                  onTap={() => {
                    setDefaultIntensity('medium');
                    setIsLogOpen(true);
                  }}
                />
                
                {/* Quick Action Buttons right below the cycle */}
                <div className="flex w-full max-w-sm gap-3 px-2">
                  <motion.button
                    whileTap={{ scale: 0.95 }}
                    onClick={() => {
                      setDefaultIntensity('medium');
                      setIsLogOpen(true);
                    }}
                    className={cn(
                      "flex-1 py-4 rounded-2xl font-bold flex items-center justify-center space-x-2 shadow-sm transition-all",
                      state !== 'HAID' ? "bg-rose-600 text-white shadow-rose-200" : "bg-gray-100 text-gray-400 cursor-not-allowed"
                    )}
                  >
                    <Droplets className="w-4 h-4" />
                    <span className="text-xs">{t('period_start')}</span>
                  </motion.button>
                  <motion.button
                    whileTap={{ scale: 0.95 }}
                    onClick={() => {
                      handleSaveLog({ intensity: 'none', timestamp: new Date().toISOString() });
                      if (user) notificationService.scheduleGhuslReminder(user);
                    }}
                    className={cn(
                      "flex-1 py-4 rounded-2xl font-bold border flex items-center justify-center space-x-2 shadow-sm transition-all",
                      state === 'HAID' ? "border-rose-200 text-rose-600 bg-white" : "border-gray-100 text-gray-300 bg-gray-50/50 cursor-not-allowed"
                    )}
                  >
                    <CheckCircle2 className="w-4 h-4" />
                    <span className="text-xs">{t('period_end')}</span>
                  </motion.button>
                </div>
              </>
            )}
          </section>

        {/* Istihadah Mode Toggle */}
        {!isPregnant && hasCyclePattern && (
          <div className="flex items-center justify-between p-4 bg-white rounded-3xl border border-black/5">
            <div className="flex items-center space-x-3">
              <div className="w-10 h-10 bg-indigo-50 rounded-2xl flex items-center justify-center text-indigo-600">
                <Droplets className="w-5 h-5" />
              </div>
              <div>
                <h4 className="text-sm font-bold text-emerald-900">{t('istihadah_mode')}</h4>
                <p className="text-[10px] text-gray-400">{t('advanced_fiqh_tracking')}</p>
              </div>
            </div>
            <button 
              onClick={() => setIsIstihadahMode(!isIstihadahMode)}
              className={cn(
                "w-12 h-6 rounded-full transition-colors relative",
                isIstihadahMode ? "bg-indigo-600" : "bg-gray-200"
              )}
            >
              <motion.div 
                animate={{ x: isIstihadahMode ? 24 : 4 }}
                className="absolute top-1 w-4 h-4 bg-white rounded-full shadow-sm"
              />
            </button>
          </div>
        )}

        {/* Istihadah Advanced Mode */}
        <AnimatePresence>
          {isIstihadahMode && !isPregnant && hasCyclePattern && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
            >
              <IstihadahMode 
                madhhab={user?.madhhab || 'HANAFI'} 
                onLogClassification={(isHaid) => {}}
              />
            </motion.div>
          )}
        </AnimatePresence>

        {/* Condition Protocols */}
        {!isPregnant && user?.reflect_health && (
          <div className="space-y-4">
            {hasPCOS && <PCOSProtocol />}
            {hasEndo && <EndoProtocol />}
          </div>
        )}

        {/* Fiqh State Banner */}
        {currentDay !== null && cycleLength !== null && haidDuration !== null && (
          <FiqhStateBanner 
            state={state} 
            madhhab={user?.madhhab || 'HANAFI'} 
            currentDay={currentDay}
            cycleLength={cycleLength}
            haidDuration={haidDuration}
          />
        )}

        {/* Dynamic Widgets */}
        <div className="space-y-4">
          <PrayerStatusWidget state={state} onOpenSettings={onOpenSettings} />
          
          <AnimatePresence mode="wait">
            {(state === 'HAID' || state === 'NIFAS') && (
              <WorshipWithoutSalah key="worship" />
            )}
          </AnimatePresence>
        </div>

        {/* Dream Interpreter */}
        <DreamInterpreterWidget onClick={onOpenDreamInterpreter} />

        {/* Niswah AI Quick Access */}
        <motion.section 
          whileTap={{ scale: 0.98 }}
          onClick={onOpenAI}
          className="p-6 bg-white rounded-[32px] shadow-xl shadow-black/5 border border-black/5 space-y-4 cursor-pointer relative overflow-hidden group"
        >
          <div className="absolute top-0 right-0 p-4 opacity-5 group-hover:opacity-10 transition-opacity">
            <MessageSquare className="w-24 h-24 text-indigo-900" />
          </div>
          <div className="flex items-center justify-between relative z-10">
            <div className="flex items-center space-x-3">
              <div className="w-10 h-10 bg-indigo-100 rounded-full flex items-center justify-center text-indigo-600">
                <Sparkles className="w-5 h-5" />
              </div>
              <div className="flex flex-col">
                <span className="font-bold text-sm text-indigo-900">{t('ask_nisa_placeholder')}</span>
                <div className="flex items-center space-x-1">
                  <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ repeat: Infinity, duration: 1 }} className="w-1 h-1 bg-indigo-400 rounded-full" />
                  <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ repeat: Infinity, duration: 1, delay: 0.2 }} className="w-1 h-1 bg-indigo-400 rounded-full" />
                  <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ repeat: Infinity, duration: 1, delay: 0.4 }} className="w-1 h-1 bg-indigo-400 rounded-full" />
                </div>
              </div>
            </div>
            <Zap className="w-5 h-5 text-amber-400 fill-amber-400" />
          </div>
          <p className="text-[10px] text-gray-400 italic relative z-10">{t('qadha_example')}</p>
        </motion.section>
      </main>

      {/* Log Bottom Sheet */}
      <LogBottomSheet 
        isOpen={isLogOpen} 
        onClose={() => {
          setIsLogOpen(false);
          setDefaultIntensity('none');
        }} 
        madhhab={user?.madhhab || 'HANAFI'} 
        onSave={handleSaveLog}
        currentState={state}
        defaultIntensity={defaultIntensity}
      />
    </div>
  );
};
