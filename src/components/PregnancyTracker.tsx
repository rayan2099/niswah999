/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  Baby, 
  Heart, 
  Sparkles, 
  ChevronRight, 
  ChevronLeft, 
  Calendar, 
  Info, 
  CheckCircle2,
  Stethoscope,
  Utensils,
  Moon
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

import { useTranslation } from '../i18n/LanguageContext.tsx';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface PregnancyTrackerProps {
  currentWeek: number;
  onLogBirth: () => void;
}

export const PregnancyTracker = ({ currentWeek, onLogBirth }: PregnancyTrackerProps) => {
  const { t } = useTranslation();
  const [selectedWeek, setSelectedWeek] = useState(currentWeek);

  const WEEK_DATA: Record<number, any> = {
    4: { stage: t('nutfah_stage'), size: t('poppy_seed'), medical: 'Implantation complete. The blastocyst is now an embryo.', islamic: t('nutfah_stage'), nutrition: 'Focus on Folate-rich foods: spinach, lentils, and citrus.', prayer: 'Standard prayer. Ensure gentle movements if feeling nauseous.', dua: 'Rabbi hab li min ladunka dhurriyyatan tayyibatan' },
    12: { stage: t('alaqah_stage'), size: t('lime'), medical: 'Fetal organs are formed and starting to function. Reflexes develop.', islamic: 'Bone formation (Quran 23:14)', nutrition: 'Increase Calcium: yogurt, cheese, and fortified plant milks.', prayer: 'If standing is difficult, you may pray sitting.', dua: 'Rabbi ija\'lni muqima as-salati wa min dhurriyyati' },
    20: { stage: t('mudgha_stage'), size: t('banana'), medical: 'Baby can hear your heartbeat and voice. Movements are felt.', islamic: 'Ruh (Soul) breathed in (Day 120)', nutrition: 'Iron is key: lean meats, beans, and dried apricots.', prayer: 'Sitting prayer recommended if balance is affected.', dua: 'Allahumma barik lana fi ma razaqtana' },
    40: { stage: t('full_term'), size: t('watermelon'), medical: 'Baby is ready for birth. Lungs are fully developed.', islamic: 'Birth — Nifas begins', nutrition: 'Dates for energy and labor support.', prayer: 'Pray in the most comfortable position allowed.', dua: 'Rabbi yassir wa la tu\'assir' }
  };

  const data = WEEK_DATA[selectedWeek] || WEEK_DATA[4]; // Fallback

  return (
    <div className="space-y-8">
      {/* Week Selector */}
      <div className="flex items-center justify-between px-2">
        <button 
          onClick={() => setSelectedWeek(Math.max(1, selectedWeek - 1))}
          className="p-2 bg-white rounded-full shadow-sm border border-black/5"
        >
          <ChevronLeft className="w-5 h-5 text-emerald-900" />
        </button>
        <div className="text-center">
          <h2 className="text-4xl font-serif font-bold text-emerald-900">{t('week')} {selectedWeek}</h2>
          <p className="text-[10px] font-bold text-emerald-600 uppercase tracking-widest">{t('trimester')} {Math.ceil(selectedWeek / 13)}</p>
        </div>
        <button 
          onClick={() => setSelectedWeek(Math.min(40, selectedWeek + 1))}
          className="p-2 bg-white rounded-full shadow-sm border border-black/5"
        >
          <ChevronRight className="w-5 h-5 text-emerald-900" />
        </button>
      </div>

      {/* Progress Bar */}
      <div className="px-4">
        <div className="h-2 bg-emerald-100 rounded-full overflow-hidden relative">
          <motion.div 
            initial={{ width: 0 }}
            animate={{ width: `${(selectedWeek / 40) * 100}%` }}
            className="h-full bg-emerald-500"
          />
          <div className="absolute inset-0 flex justify-between px-1">
            {[10, 20, 30].map(w => (
              <div key={w} className="w-1 h-full bg-white/30" />
            ))}
          </div>
        </div>
      </div>

      {/* Main Card */}
      <motion.div 
        key={selectedWeek}
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="bg-white rounded-[40px] p-8 shadow-xl shadow-black/5 border border-black/5 space-y-8"
      >
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('islamic_milestone')}</span>
            <h3 className="text-xl font-serif font-bold text-emerald-900">{data.islamic}</h3>
          </div>
          <div className="w-12 h-12 bg-emerald-50 rounded-2xl flex items-center justify-center text-emerald-600">
            <Baby className="w-6 h-6" />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="p-4 bg-emerald-50 rounded-3xl space-y-2">
            <div className="flex items-center space-x-2 text-emerald-600">
              <Stethoscope className="w-4 h-4" />
              <span className="text-[10px] font-bold uppercase tracking-widest">{t('medical')}</span>
            </div>
            <p className="text-xs text-emerald-900 leading-relaxed">{data.medical}</p>
          </div>
          <div className="p-4 bg-amber-50 rounded-3xl space-y-2">
            <div className="flex items-center space-x-2 text-amber-600">
              <Utensils className="w-4 h-4" />
              <span className="text-[10px] font-bold uppercase tracking-widest">{t('nutrition')}</span>
            </div>
            <p className="text-xs text-amber-900 leading-relaxed">{data.nutrition}</p>
          </div>
        </div>

        <div className="space-y-4">
          <div className="flex items-start space-x-4">
            <div className="w-8 h-8 bg-indigo-50 rounded-full flex items-center justify-center flex-shrink-0">
              <Moon className="w-4 h-4 text-indigo-600" />
            </div>
            <div className="space-y-1">
              <h4 className="text-sm font-bold text-indigo-900">{t('prayer_modification')}</h4>
              <p className="text-xs text-indigo-600/60 leading-relaxed">{data.prayer}</p>
            </div>
          </div>
          <div className="flex items-start space-x-4">
            <div className="w-8 h-8 bg-rose-50 rounded-full flex items-center justify-center flex-shrink-0">
              <Heart className="w-4 h-4 text-rose-600" />
            </div>
            <div className="space-y-1">
              <h4 className="text-sm font-bold text-rose-900">{t('dua_for_baby')}</h4>
              <p className="text-xs italic text-rose-600/60 leading-relaxed">"{data.dua}"</p>
            </div>
          </div>
        </div>

        <button 
          onClick={onLogBirth}
          className="w-full py-4 bg-emerald-600 text-white rounded-2xl font-bold shadow-lg shadow-emerald-200 flex items-center justify-center space-x-2"
        >
          <Sparkles className="w-4 h-4" />
          <span>{t('log_birth_nifas')}</span>
        </button>
      </motion.div>
    </div>
  );
};
