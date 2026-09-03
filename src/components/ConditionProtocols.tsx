/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { 
  Zap, 
  Heart, 
  Sparkles, 
  ChevronRight, 
  ChevronLeft, 
  Check, 
  Info, 
  AlertCircle,
  Stethoscope,
  Calendar,
  BookOpen,
  Utensils,
  Activity,
  MapPin
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const PCOSProtocol = () => {
  const { t } = useTranslation();
  return (
    <div className="space-y-6">
      <div className="p-6 bg-amber-50 rounded-[40px] border border-amber-100 space-y-6">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-amber-100 rounded-2xl flex items-center justify-center text-amber-600">
            <Zap className="w-6 h-6" />
          </div>
          <div>
            <h3 className="text-lg font-serif font-bold text-amber-900">{t('pcos_protocol')}</h3>
            <p className="text-[10px] font-bold text-amber-600 uppercase tracking-widest">{t('islamic_wellness_mode')}</p>
          </div>
        </div>

        <div className="space-y-4">
          <div className="p-4 bg-white rounded-3xl border border-amber-100 space-y-2">
            <div className="flex items-center space-x-2 text-amber-600">
              <Calendar className="w-4 h-4" />
              <span className="text-[10px] font-bold uppercase tracking-widest">{t('cycle_expectations')}</span>
            </div>
            <p className="text-xs text-amber-900 leading-relaxed">
              {t('pcos_cycle_desc')}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="p-4 bg-white rounded-3xl border border-amber-100 space-y-2">
              <div className="flex items-center space-x-2 text-amber-600">
                <Utensils className="w-4 h-4" />
                <span className="text-[10px] font-bold uppercase tracking-widest">{t('nutrition')}</span>
              </div>
              <p className="text-[10px] text-amber-900 leading-relaxed">{t('pcos_nutrition_desc')}</p>
            </div>
            <div className="p-4 bg-white rounded-3xl border border-amber-100 space-y-2">
              <div className="flex items-center space-x-2 text-amber-600">
                <Activity className="w-4 h-4" />
                <span className="text-[10px] font-bold uppercase tracking-widest">{t('exercise')}</span>
              </div>
              <p className="text-[10px] text-amber-900 leading-relaxed">{t('pcos_exercise_desc')}</p>
            </div>
          </div>

          <div className="p-4 bg-white rounded-3xl border border-amber-100 space-y-3">
            <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('supplement_tracker')}</h4>
            <div className="flex flex-wrap gap-2">
              {['Inositol', 'Vitamin D', 'Zinc', 'Magnesium'].map(s => (
                <div key={s} className="px-3 py-1 bg-amber-50 rounded-full text-[10px] font-bold text-amber-600 border border-amber-100 flex items-center space-x-1">
                  <Check className="w-3 h-3" />
                  <span>{s}</span>
                </div>
              ))}
            </div>
          </div>

          <button className="w-full py-4 bg-white rounded-2xl border border-amber-100 text-amber-900 font-bold text-xs uppercase tracking-widest flex items-center justify-center space-x-2">
            <Stethoscope className="w-4 h-4" />
            <span>{t('book_muslim_endo')}</span>
          </button>
        </div>
      </div>
    </div>
  );
};

export const EndoProtocol = () => {
  const { t } = useTranslation();
  const [selectedArea, setSelectedArea] = useState<string | null>(null);

  return (
    <div className="space-y-6">
      <div className="p-6 bg-rose-50 rounded-[40px] border border-rose-100 space-y-6">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-rose-100 rounded-2xl flex items-center justify-center text-rose-600">
            <Heart className="w-6 h-6" />
          </div>
          <div>
            <h3 className="text-lg font-serif font-bold text-rose-900">{t('endo_protocol')}</h3>
            <p className="text-[10px] font-bold text-rose-600 uppercase tracking-widest">{t('pain_management_active')}</p>
          </div>
        </div>

        <div className="space-y-4">
          <div className="p-6 bg-white rounded-[32px] border border-rose-100 space-y-4">
            <h4 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest text-center">{t('pain_location_map')}</h4>
            <div className="flex justify-center space-x-8">
              {/* Simplified Body Map */}
              <div className="relative w-24 h-48 bg-rose-50 rounded-[40px] border border-rose-100 flex items-center justify-center">
                <div className="absolute top-4 w-8 h-8 bg-rose-100 rounded-full" />
                <div className="absolute top-14 w-12 h-20 bg-rose-100 rounded-2xl" />
                <div className="absolute bottom-4 w-4 h-16 bg-rose-100 rounded-full left-6" />
                <div className="absolute bottom-4 w-4 h-16 bg-rose-100 rounded-full right-6" />
                
                {/* Tappable Areas */}
                <motion.button 
                  whileTap={{ scale: 0.9 }}
                  onClick={() => setSelectedArea('pelvis')}
                  className={cn(
                    "absolute top-24 w-8 h-8 rounded-full border-2 transition-all",
                    selectedArea === 'pelvis' ? "bg-rose-500 border-rose-500 shadow-lg shadow-rose-200" : "bg-white/50 border-rose-200"
                  )}
                />
              </div>
              <div className="space-y-2 flex flex-col justify-center">
                <p className="text-[10px] font-bold text-rose-900">{t('front_view')}</p>
                <p className="text-[8px] text-gray-400">{t('tap_affected_areas')}</p>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="p-4 bg-white rounded-3xl border border-rose-100 space-y-2">
              <div className="flex items-center space-x-2 text-rose-600">
                <Calendar className="w-4 h-4" />
                <span className="text-[10px] font-bold uppercase tracking-widest">{t('flare_prediction')}</span>
              </div>
              <p className="text-[10px] text-rose-900 font-bold">{t('next_flare')}: 3 {t('days')}</p>
            </div>
            <div className="p-4 bg-white rounded-3xl border border-rose-100 space-y-2">
              <div className="flex items-center space-x-2 text-rose-600">
                <BookOpen className="w-4 h-4" />
                <span className="text-[10px] font-bold uppercase tracking-widest">{t('symptom_report')}</span>
              </div>
              <p className="text-[10px] text-rose-900 font-bold">{t('generate_pdf')}</p>
            </div>
          </div>

          <button className="w-full py-4 bg-white rounded-2xl border border-rose-100 text-rose-900 font-bold text-xs uppercase tracking-widest flex items-center justify-center space-x-2">
            <Stethoscope className="w-4 h-4" />
            <span>{t('book_muslim_gyno')}</span>
          </button>
        </div>
      </div>
    </div>
  );
};
