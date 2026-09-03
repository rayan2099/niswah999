/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { 
  Droplets, 
  Sparkles, 
  ChevronRight, 
  ChevronLeft, 
  Check, 
  Info, 
  AlertCircle,
  Stethoscope,
  Calendar,
  BookOpen
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface IstihadahModeProps {
  madhhab: string;
  onLogClassification: (isHaid: boolean) => void;
}

export const IstihadahMode = ({ madhhab, onLogClassification }: IstihadahModeProps) => {
  const { t } = useTranslation();
  const [classification, setClassification] = useState<'strong' | 'weak' | null>(null);
  const [showResult, setShowResult] = useState(false);

  const isTamyiz = ['SHAFI', 'MALIKI', 'HANBALI'].includes(madhhab);

  const handleClassify = (type: 'strong' | 'weak') => {
    setClassification(type);
    setShowResult(true);
    onLogClassification(type === 'strong');
  };

  return (
    <div className="space-y-6">
      <div className="p-6 bg-indigo-50 rounded-[40px] border border-indigo-100 space-y-4">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-indigo-100 rounded-2xl flex items-center justify-center text-indigo-600">
            <Droplets className="w-6 h-6" />
          </div>
          <div>
            <h3 className="text-lg font-serif font-bold text-indigo-900">{t('istihadah_support')}</h3>
            <p className="text-[10px] font-bold text-indigo-600 uppercase tracking-widest">{t('advanced_mode_active')}</p>
          </div>
        </div>

        {isTamyiz ? (
          <div className="space-y-4">
            <p className="text-sm text-indigo-900 leading-relaxed">
              {t('tamyiz_instruction').replace('{{madhhab}}', madhhab)}
            </p>
            <div className="grid grid-cols-2 gap-3">
              <motion.button
                whileTap={{ scale: 0.95 }}
                onClick={() => handleClassify('strong')}
                className="p-4 bg-white rounded-3xl border border-indigo-100 text-left space-y-2"
              >
                <div className="w-8 h-8 bg-rose-100 rounded-xl flex items-center justify-center text-rose-600">
                  <Droplets className="w-5 h-5 fill-rose-600" />
                </div>
                <h4 className="text-xs font-bold text-indigo-900">{t('strong_blood')}</h4>
                <p className="text-[8px] text-gray-400">{t('strong_blood_desc')}</p>
              </motion.button>
              <motion.button
                whileTap={{ scale: 0.95 }}
                onClick={() => handleClassify('weak')}
                className="p-4 bg-white rounded-3xl border border-indigo-100 text-left space-y-2"
              >
                <div className="w-8 h-8 bg-rose-50 rounded-xl flex items-center justify-center text-rose-400">
                  <Droplets className="w-5 h-5" />
                </div>
                <h4 className="text-xs font-bold text-indigo-900">{t('weak_blood')}</h4>
                <p className="text-[8px] text-gray-400">{t('weak_blood_desc')}</p>
              </motion.button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <p className="text-sm text-indigo-900 leading-relaxed">
              {t('adah_instruction')}
            </p>
            <div className="p-4 bg-white rounded-3xl border border-indigo-100 space-y-2 text-center">
              <p className="text-xs text-indigo-600/60">
                {t('habit_status').replace('{{habit}}', '7').replace('{{day}}', '8')}
              </p>
              <div className="flex items-center justify-center space-x-2 text-indigo-900 font-bold">
                <AlertCircle className="w-4 h-4 text-amber-500" />
                <span>{t('state_istihadah')}</span>
              </div>
            </div>
          </div>
        )}

        <AnimatePresence>
          {showResult && classification && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              className="pt-4 border-t border-indigo-100 space-y-4"
            >
              <div className={cn(
                "p-4 rounded-3xl flex items-center space-x-4",
                classification === 'strong' ? "bg-rose-50 text-rose-900" : "bg-emerald-50 text-emerald-900"
              )}>
                <div className="w-10 h-10 rounded-full bg-white flex items-center justify-center flex-shrink-0">
                  {classification === 'strong' ? <Droplets className="w-5 h-5" /> : <Sparkles className="w-5 h-5" />}
                </div>
                <div>
                  <h4 className="text-sm font-bold">
                    {classification === 'strong' ? t('counts_as_haid') : t('is_istihadah')}
                  </h4>
                  <p className="text-[10px] opacity-70">
                    {classification === 'strong' ? t('prayer_not_required') : t('prayer_required_wudu')}
                  </p>
                </div>
              </div>
              <div className="flex items-center justify-between p-4 bg-white rounded-3xl border border-indigo-100">
                <div className="flex items-center space-x-2">
                  <BookOpen className="w-4 h-4 text-indigo-600" />
                  <span className="text-[10px] font-bold text-indigo-900 uppercase tracking-widest">{t('complex_case')}</span>
                </div>
                <button className="text-[10px] font-bold text-indigo-600 uppercase tracking-widest">{t('consult_scholar')}</button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
};
