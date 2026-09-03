/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { 
  X, 
  ChevronRight, 
  ChevronLeft, 
  Check, 
  Lock, 
  Sparkles, 
  Play, 
  BookOpen, 
  Heart, 
  ShieldCheck, 
  Calendar, 
  ArrowRight,
  Info,
  Zap
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface Journey {
  id: string;
  title: string;
  description: string;
  length: string;
  premium: boolean;
  progress?: number;
  lessons: any[];
}

export const GuidedJourneys = ({ isOpen, onClose, isPremium }: { isOpen: boolean, onClose: () => void, isPremium: boolean }) => {
  const { t } = useTranslation();
  const [selectedJourney, setSelectedJourney] = useState<Journey | null>(null);
  const [activeLesson, setActiveLesson] = useState<any>(null);

  const JOURNEYS: Journey[] = [
    {
      id: '1',
      title: t('journey_1_title'),
      description: t('journey_1_desc'),
      length: "30 days",
      premium: false,
      progress: 12,
      lessons: [
        { id: '1-1', title: t('lesson_1_1'), type: 'video', content: '...' },
        { id: '1-2', title: t('lesson_1_2'), type: 'article', content: '...' }
      ]
    },
    {
      id: '2',
      title: t('journey_2_title'),
      description: t('journey_2_desc'),
      length: "7 days",
      premium: true,
      progress: 0,
      lessons: [
        { id: '2-1', title: t('lesson_2_1'), type: 'article', content: '...' },
        { id: '2-2', title: t('lesson_2_2'), type: 'video', content: '...' }
      ]
    },
    {
      id: '3',
      title: t('journey_3_title'),
      description: t('journey_3_desc'),
      length: "Month-by-month",
      premium: true,
      progress: 0,
      lessons: [
        { id: '3-1', title: t('lesson_3_1'), type: 'article', content: '...' }
      ]
    },
    {
      id: '4',
      title: t('journey_4_title'),
      description: t('journey_4_desc'),
      length: "40 days",
      premium: true,
      progress: 0,
      lessons: [
        { id: '4-1', title: t('lesson_4_1'), type: 'article', content: '...' }
      ]
    },
    {
      id: '5',
      title: t('journey_5_title'),
      description: t('journey_5_desc'),
      length: "Ongoing",
      premium: true,
      progress: 0,
      lessons: [
        { id: '5-1', title: t('lesson_5_1'), type: 'article', content: '...' }
      ]
    },
    {
      id: '6',
      title: t('journey_6_title'),
      description: t('journey_6_desc'),
      length: "90 days",
      premium: true,
      progress: 0,
      lessons: [
        { id: '6-1', title: t('lesson_6_1'), type: 'article', content: '...' }
      ]
    }
  ];

  if (!isOpen) return null;

  if (activeLesson) {
    return (
      <motion.div 
        initial={{ y: '100%' }}
        animate={{ y: 0 }}
        exit={{ y: '100%' }}
        className="fixed inset-0 z-[400] bg-[#FDFCFB] flex flex-col"
      >
        <header className="p-6 flex items-center justify-between border-b border-black/5">
          <button onClick={() => setActiveLesson(null)} className="p-2 hover:bg-gray-100 rounded-full">
            <X className="w-6 h-6 text-emerald-900" />
          </button>
          <div className="text-center">
            <p className="text-[10px] font-bold text-emerald-600 uppercase tracking-widest">
              {t('lesson_count').replace('{{current}}', '1').replace('{{total}}', '7')}
            </p>
            <h2 className="text-sm font-bold text-emerald-900">{activeLesson.title}</h2>
          </div>
          <div className="w-10 h-10" />
        </header>

        <div className="flex-1 overflow-y-auto p-8 space-y-8">
          <div className="aspect-video bg-emerald-100 rounded-[32px] flex items-center justify-center relative overflow-hidden">
            <Play className="w-12 h-12 text-emerald-600 fill-emerald-600" />
            <div className="absolute inset-0 bg-black/10" />
          </div>
          <div className="space-y-4">
            <h3 className="text-2xl font-serif font-bold text-emerald-900">{activeLesson.title}</h3>
            <p className="text-sm text-gray-500 leading-relaxed">
              In this lesson, we explore the foundational concepts of {activeLesson.title} within the context of your Fiqh school. Understanding these basics is essential for accurate tracking and fulfilling your spiritual obligations.
            </p>
          </div>
          <div className="p-6 bg-emerald-50 rounded-3xl border border-emerald-100 space-y-4">
            <h4 className="text-sm font-bold text-emerald-900">{t('daily_checkin')}</h4>
            <p className="text-xs text-emerald-600/60">{t('lesson_helpful_prompt')}</p>
            <div className="flex space-x-3">
              <button className="flex-1 py-3 bg-white rounded-xl text-xs font-bold text-emerald-900 border border-emerald-100">{t('yes_very')}</button>
              <button className="flex-1 py-3 bg-white rounded-xl text-xs font-bold text-emerald-900 border border-emerald-100">{t('somewhat')}</button>
            </div>
          </div>
        </div>

        <div className="p-8 bg-white border-t border-black/5">
          <button 
            onClick={() => setActiveLesson(null)}
            className="w-full py-4 bg-emerald-600 text-white rounded-2xl font-bold shadow-lg shadow-emerald-200 flex items-center justify-center space-x-2"
          >
            <span>{t('complete_today')}</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </motion.div>
    );
  }

  return (
    <motion.div 
      initial={{ y: '100%' }}
      animate={{ y: 0 }}
      exit={{ y: '100%' }}
      className="fixed inset-0 z-[300] bg-[#FDFCFB] flex flex-col"
    >
      <header className="p-6 flex items-center justify-between">
        <button onClick={onClose} className="p-2 hover:bg-gray-100 rounded-full">
          <X className="w-6 h-6 text-emerald-900" />
        </button>
        <h2 className="text-xl font-serif font-bold text-emerald-900">{t('guided_journeys')}</h2>
        <div className="w-10 h-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-6">
        <div className="p-6 bg-gradient-to-br from-emerald-600 to-teal-700 rounded-[40px] text-white space-y-4 relative overflow-hidden">
          <Sparkles className="absolute top-0 right-0 p-6 w-32 h-32 opacity-10" />
          <div className="relative z-10 space-y-2">
            <h3 className="text-2xl font-serif font-bold">{t('path_to_clarity_title')}</h3>
            <p className="text-sm text-emerald-100/80 leading-relaxed max-w-[240px]">{t('path_to_clarity_desc')}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4">
          {JOURNEYS.map((j) => (
            <motion.button
              key={j.id}
              whileTap={{ scale: 0.98 }}
              onClick={() => {
                if (!j.premium || isPremium) {
                  setSelectedJourney(j);
                  setActiveLesson(j.lessons[0]);
                }
              }}
              className="p-6 bg-white rounded-[32px] border border-black/5 shadow-sm text-left space-y-4 relative group"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-3">
                  <div className="w-12 h-12 bg-emerald-50 rounded-2xl flex items-center justify-center text-emerald-600">
                    {j.id === '1' && <Calendar className="w-6 h-6" />}
                    {j.id === '2' && <BookOpen className="w-6 h-6" />}
                    {j.id === '3' && <Heart className="w-6 h-6" />}
                    {j.id === '4' && <Sparkles className="w-6 h-6" />}
                    {j.id === '5' && <ShieldCheck className="w-6 h-6" />}
                    {j.id === '6' && <Zap className="w-6 h-6" />}
                  </div>
                  <div>
                    <h4 className="font-bold text-emerald-900">{j.title}</h4>
                    <p className="text-[10px] text-emerald-600 font-bold uppercase tracking-widest">{j.length}</p>
                  </div>
                </div>
                {j.premium && !isPremium && <Lock className="w-5 h-5 text-gray-300" />}
              </div>
              <p className="text-xs text-gray-400 leading-relaxed">{j.description}</p>
              {j.progress ? (
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-[8px] font-bold uppercase tracking-widest text-emerald-600">
                    <span>{t('progress_label')}</span>
                    <span>{j.progress}%</span>
                  </div>
                  <div className="h-1.5 bg-emerald-50 rounded-full overflow-hidden">
                    <div className="h-full bg-emerald-500" style={{ width: `${j.progress}%` }} />
                  </div>
                </div>
              ) : (
                <div className="flex items-center space-x-2 text-[10px] font-bold uppercase tracking-widest text-emerald-600">
                  <span>{t('start_journey')}</span>
                  <ChevronRight className="w-3 h-3" />
                </div>
              )}
            </motion.button>
          ))}
        </div>
      </div>
    </motion.div>
  );
};
