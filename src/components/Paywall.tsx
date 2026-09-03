/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  X, 
  Check, 
  Sparkles, 
  Zap, 
  Shield, 
  Heart, 
  ChevronRight,
  CreditCard,
  RefreshCw
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

import { useTranslation } from '../i18n/LanguageContext.tsx';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface PaywallProps {
  isOpen: boolean;
  onClose: () => void;
  onPurchase: (plan: string) => void;
}

export const Paywall = ({ isOpen, onClose, onPurchase }: PaywallProps) => {
  const { t } = useTranslation();
  const [selectedPlan, setSelectedPlan] = useState<'monthly' | 'annual'>('annual');

  const features = [
    { icon: Sparkles, text: t('feat_advanced_fiqh') },
    { icon: Zap, text: t('feat_journeys_insights') },
    { icon: Shield, text: t('feat_secret_section') },
    { icon: Heart, text: t('feat_pcos_endo') },
    { icon: CreditCard, text: t('feat_fsa_hsa') }
  ];

  const plans = [
    { id: 'monthly', name: t('plan_monthly'), price: '$9.99', sub: '/ month', price_desc: t('plan_price_monthly') },
    { id: 'annual', name: t('plan_annual'), price: '$79.99', sub: '/ year', badge: t('save_20'), price_desc: t('plan_price_annual') }
  ];

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[500] bg-emerald-900/40 backdrop-blur-xl flex items-end justify-center"
        >
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 20, stiffness: 200 }}
            className="w-full max-w-lg bg-white rounded-t-[40px] p-8 space-y-8 max-h-[95vh] overflow-y-auto no-scrollbar"
          >
            <div className="flex justify-between items-center">
              <div className="w-12 h-12 bg-emerald-100 rounded-2xl flex items-center justify-center text-emerald-600">
                <Sparkles className="w-6 h-6" />
              </div>
              <button onClick={onClose} className="p-2 bg-gray-100 rounded-full">
                <X className="w-5 h-5 text-gray-400" />
              </button>
            </div>

            <div className="space-y-2">
              <h2 className="text-3xl font-serif font-bold text-emerald-900">{t('unlock_plus_title')}</h2>
              <p className="text-sm text-emerald-600/60 leading-relaxed">
                {t('unlock_plus_desc')}
              </p>
            </div>

            <div className="space-y-4">
              {features.map((f, i) => (
                <div key={i} className="flex items-center space-x-4">
                  <div className="w-8 h-8 bg-emerald-50 rounded-xl flex items-center justify-center text-emerald-600">
                    <f.icon className="w-4 h-4" />
                  </div>
                  <span className="text-sm font-medium text-emerald-900">{f.text}</span>
                </div>
              ))}
            </div>

            <div className="space-y-3">
              {plans.map((p) => (
                <motion.button
                  key={p.id}
                  whileTap={{ scale: 0.98 }}
                  onClick={() => setSelectedPlan(p.id as any)}
                  className={cn(
                    "w-full p-5 rounded-3xl border-2 transition-all text-left relative overflow-hidden",
                    selectedPlan === p.id ? "border-emerald-500 bg-emerald-50" : "border-black/5 bg-white"
                  )}
                >
                  {p.badge && (
                    <div className="absolute top-0 right-0 px-4 py-1 bg-emerald-500 text-white text-[8px] font-bold uppercase tracking-widest rounded-bl-xl">
                      {p.badge}
                    </div>
                  )}
                  <div className="flex items-center justify-between">
                    <div>
                      <h4 className="text-sm font-bold text-emerald-900">{p.name}</h4>
                      <p className="text-[10px] text-gray-400">{p.price_desc}</p>
                    </div>
                    <div className={cn(
                      "w-6 h-6 rounded-full border-2 flex items-center justify-center",
                      selectedPlan === p.id ? "border-emerald-500 bg-emerald-500" : "border-gray-200"
                    )}>
                      {selectedPlan === p.id && <Check className="w-4 h-4 text-white" />}
                    </div>
                  </div>
                </motion.button>
              ))}
            </div>

            <div className="space-y-4">
              <button 
                onClick={() => onPurchase(selectedPlan)}
                className="w-full py-5 bg-emerald-600 text-white rounded-2xl font-bold shadow-xl shadow-emerald-200 flex items-center justify-center space-x-2"
              >
                <span>{t('start_free_trial')}</span>
                <ChevronRight className="w-4 h-4" />
              </button>
              
              <div className="flex items-center justify-center space-x-6 text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                <button className="hover:text-emerald-600">{t('terms_of_service')}</button>
                <button className="hover:text-emerald-600 flex items-center space-x-1">
                  <RefreshCw className="w-3 h-3" />
                  <span>{t('restore_purchase')}</span>
                </button>
              </div>
            </div>
            
            <div className="p-4 bg-gray-50 rounded-2xl border border-black/5 flex items-center justify-center space-x-2">
              <div className="w-8 h-8 bg-white rounded-lg flex items-center justify-center text-emerald-600 border border-black/5">
                <CreditCard className="w-4 h-4" />
              </div>
              <span className="text-[10px] font-bold text-gray-500 uppercase tracking-widest">{t('fsa_hsa_eligible')}</span>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
