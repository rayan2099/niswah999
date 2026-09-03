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
  Droplets, 
  Sparkles, 
  ArrowRight,
  Info,
  Waves,
  Hand,
  User,
  ShieldCheck
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface GhuslGuideProps {
  isOpen: boolean;
  onClose: () => void;
  onComplete: () => void;
  madhhab: string;
}

export const GhuslGuide = ({ isOpen, onClose, onComplete, madhhab }: GhuslGuideProps) => {
  const { t } = useTranslation();
  const [currentStep, setCurrentStep] = useState(0);
  const [counts, setCounts] = useState<Record<number, number>>({});
  const [wuduChecks, setWuduChecks] = useState<Record<number, boolean>>({});
  const [finalChecks, setFinalChecks] = useState<Record<number, boolean>>({});
  const [isCompleted, setIsCompleted] = useState(false);
  
  const STEPS = [
    {
      id: 1,
      title: t('ghusl_niyyah_title'),
      arabic: t('ghusl_niyyah_arabic'),
      transliteration: t('ghusl_niyyah_transliteration'),
      english: t('ghusl_niyyah_english'),
      instruction: t('ghusl_niyyah_instruction'),
      visual: "hands-raised"
    },
    {
      id: 2,
      title: t('ghusl_wash_hands_title'),
      instruction: t('ghusl_wash_hands_instruction'),
      counter: 3,
      visual: "wash-hands"
    },
    {
      id: 3,
      title: t('ghusl_remove_impurity_title'),
      instruction: t('ghusl_remove_impurity_instruction'),
      visual: "cleanse"
    },
    {
      id: 4,
      title: t('ghusl_wudu_title'),
      instruction: t('ghusl_wudu_instruction'),
      subSteps: [
        t('ghusl_wudu_step1'),
        t('ghusl_wudu_step2'),
        t('ghusl_wudu_step3'),
        t('ghusl_wudu_step4'),
        t('ghusl_wudu_step5'),
        t('ghusl_wudu_step6'),
        t('ghusl_wudu_step7')
      ],
      visual: "wudu"
    },
    {
      id: 5,
      title: t('ghusl_right_side_title'),
      instruction: t('ghusl_right_side_instruction'),
      reminder: t('ghusl_right_side_reminder'),
      counter: 3,
      visual: "pour-right"
    },
    {
      id: 6,
      title: t('ghusl_left_side_title'),
      instruction: t('ghusl_left_side_instruction'),
      counter: 3,
      visual: "pour-left"
    },
    {
      id: 7,
      title: t('ghusl_full_check_title'),
      instruction: t('ghusl_full_check_instruction'),
      checklist: [
        t('ghusl_check1'),
        t('ghusl_check2'),
        t('ghusl_check3'),
        t('ghusl_check4'),
        t('ghusl_check5')
      ],
      visual: "check"
    }
  ];

  // Special Toggles
  const [hasLocs, setHasLocs] = useState(false);
  const [hasAcrylics, setHasAcrylics] = useState(false);
  const [hasWound, setHasWound] = useState(false);

  const step = STEPS[currentStep];
  const progress = ((currentStep + 1) / STEPS.length) * 100;

  const handleNext = () => {
    if (currentStep < STEPS.length - 1) {
      setCurrentStep(prev => prev + 1);
      // Trigger haptic feedback (simulated)
    } else {
      setIsCompleted(true);
    }
  };

  const handleBack = () => {
    if (currentStep > 0) {
      setCurrentStep(prev => prev - 1);
    }
  };

  const handleCount = () => {
    const currentCount = counts[currentStep] || 0;
    if (currentCount < (step.counter || 0)) {
      setCounts({ ...counts, [currentStep]: currentCount + 1 });
      // Haptic feedback
    }
  };

  const isStepComplete = () => {
    if (step.counter) return (counts[currentStep] || 0) >= step.counter;
    if (step.subSteps) return Object.keys(wuduChecks).length === step.subSteps.length;
    if (step.checklist) return Object.keys(finalChecks).length === step.checklist.length;
    return true;
  };

  if (!isOpen) return null;

  if (isCompleted) {
    return (
      <motion.div 
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        className="fixed inset-0 z-[300] bg-emerald-600 flex flex-col items-center justify-center p-8 text-center text-white"
      >
        <motion.div
          initial={{ scale: 0.5, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', damping: 15 }}
          className="w-24 h-24 bg-white/20 rounded-full flex items-center justify-center mb-8"
        >
          <Sparkles className="w-12 h-12 text-white" />
        </motion.div>
        <h2 className="text-4xl font-serif font-bold mb-4">{t('alhamdulillah')}</h2>
        <p className="text-xl text-emerald-100 mb-12">{t('tahara_state')}</p>
        <button 
          onClick={onComplete}
          className="px-12 py-4 bg-white text-emerald-700 rounded-full font-bold shadow-xl shadow-emerald-900/20"
        >
          {t('return_home')}
        </button>
        
        {/* Particles Animation */}
        {[...Array(20)].map((_, i) => (
          <motion.div
            key={i}
            initial={{ 
              x: Math.random() * 400 - 200, 
              y: Math.random() * 400 - 200,
              scale: 0,
              opacity: 0
            }}
            animate={{ 
              y: [null, -500],
              scale: [0, 1, 0],
              opacity: [0, 1, 0]
            }}
            transition={{ 
              duration: 2 + Math.random() * 2,
              repeat: Infinity,
              delay: Math.random() * 2
            }}
            className="absolute w-2 h-2 bg-amber-300 rounded-full"
          />
        ))}
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
      {/* Header */}
      <header className="p-6 flex items-center justify-between">
        <button onClick={onClose} className="p-2 hover:bg-gray-100 rounded-full">
          <X className="w-6 h-6 text-emerald-900" />
        </button>
        <div className="flex-1 px-8">
          <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
            <motion.div 
              animate={{ width: `${progress}%` }}
              className="h-full bg-emerald-500"
            />
          </div>
        </div>
        <div className="text-xs font-bold text-emerald-600 uppercase tracking-widest">
          {currentStep + 1}/{STEPS.length}
        </div>
      </header>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-8 py-4">
        <AnimatePresence mode="wait">
          <motion.div
            key={currentStep}
            initial={{ x: 50, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: -50, opacity: 0 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-serif font-bold text-emerald-900">{step.title}</h2>
              <p className="text-sm text-gray-500 leading-relaxed">{step.instruction}</p>
            </div>

            {/* Visual Placeholder */}
            <div className="aspect-square bg-emerald-50 rounded-[40px] flex items-center justify-center relative overflow-hidden">
              <motion.div 
                animate={{ 
                  scale: [1, 1.05, 1],
                  rotate: [0, 2, 0]
                }}
                transition={{ repeat: Infinity, duration: 4 }}
                className="text-emerald-200"
              >
                {step.visual === 'hands-raised' && <Hand className="w-32 h-32" />}
                {step.visual === 'wash-hands' && <Waves className="w-32 h-32" />}
                {step.visual === 'wudu' && <Droplets className="w-32 h-32" />}
                {step.visual === 'pour-right' && <ChevronRight className="w-32 h-32" />}
                {step.visual === 'pour-left' && <ChevronLeft className="w-32 h-32" />}
                {step.visual === 'check' && <ShieldCheck className="w-32 h-32" />}
              </motion.div>
            </div>

            {/* Step Specific UI */}
            {step.arabic && (
              <div className="p-6 bg-white rounded-3xl border border-emerald-100 text-center space-y-4">
                <p className="text-2xl font-serif text-emerald-900" dir="rtl">{step.arabic}</p>
                <p className="text-xs italic text-emerald-600">{step.transliteration}</p>
                <p className="text-sm text-gray-600">{step.english}</p>
              </div>
            )}

            {step.counter && (
              <div className="flex flex-col items-center space-y-4">
                <div className="flex space-x-4">
                  {[1, 2, 3].map((i) => (
                    <motion.div 
                      key={i}
                      animate={{ 
                        scale: (counts[currentStep] || 0) >= i ? 1.1 : 1,
                        backgroundColor: (counts[currentStep] || 0) >= i ? '#10b981' : '#f3f4f6'
                      }}
                      className="w-12 h-12 rounded-full flex items-center justify-center font-bold text-white"
                    >
                      {(counts[currentStep] || 0) >= i ? <Check className="w-6 h-6" /> : <span className="text-gray-400">{i}</span>}
                    </motion.div>
                  ))}
                </div>
                <button 
                  onClick={handleCount}
                  disabled={(counts[currentStep] || 0) >= 3}
                  className="px-8 py-3 bg-emerald-100 text-emerald-700 rounded-full font-bold text-sm uppercase tracking-widest"
                >
                  {t('tap_to_wash')}
                </button>
                {step.reminder && (
                  <div className="flex items-center space-x-2 text-[10px] text-amber-600 font-bold uppercase tracking-widest bg-amber-50 px-4 py-2 rounded-full">
                    <Info className="w-3 h-3" />
                    <span>{step.reminder}</span>
                  </div>
                )}
              </div>
            )}

            {step.subSteps && (
              <div className="space-y-3">
                {step.subSteps.map((s, i) => (
                  <button 
                    key={i}
                    onClick={() => setWuduChecks({ ...wuduChecks, [i]: !wuduChecks[i] })}
                    className={cn(
                      "w-full p-4 rounded-2xl border flex items-center justify-between transition-all",
                      wuduChecks[i] ? "bg-emerald-50 border-emerald-200" : "bg-white border-black/5"
                    )}
                  >
                    <span className={cn("text-sm font-bold", wuduChecks[i] ? "text-emerald-900" : "text-gray-400")}>{s}</span>
                    <div className={cn(
                      "w-6 h-6 rounded-full border flex items-center justify-center",
                      wuduChecks[i] ? "bg-emerald-500 border-emerald-500 text-white" : "border-gray-200"
                    )}>
                      {wuduChecks[i] && <Check className="w-4 h-4" />}
                    </div>
                  </button>
                ))}
              </div>
            )}

            {step.checklist && (
              <div className="space-y-3">
                {step.checklist.map((s, i) => (
                  <button 
                    key={i}
                    onClick={() => setFinalChecks({ ...finalChecks, [i]: !finalChecks[i] })}
                    className={cn(
                      "w-full p-4 rounded-2xl border flex items-center justify-between transition-all",
                      finalChecks[i] ? "bg-emerald-50 border-emerald-200" : "bg-white border-black/5"
                    )}
                  >
                    <span className={cn("text-sm font-bold", finalChecks[i] ? "text-emerald-900" : "text-gray-400")}>{s}</span>
                    <div className={cn(
                      "w-6 h-6 rounded-full border flex items-center justify-center",
                      finalChecks[i] ? "bg-emerald-500 border-emerald-500 text-white" : "border-gray-200"
                    )}>
                      {finalChecks[i] && <Check className="w-4 h-4" />}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </motion.div>
        </AnimatePresence>
      </div>

      {/* Footer Controls */}
      <div className="p-8 bg-white border-t border-black/5 space-y-6">
        {/* Special Toggles */}
        <div className="flex overflow-x-auto no-scrollbar space-x-3 pb-2">
          <SpecialToggle active={hasLocs} onClick={() => setHasLocs(!hasLocs)} label={t('locs_braids')} />
          <SpecialToggle active={hasAcrylics} onClick={() => setHasAcrylics(!hasAcrylics)} label={t('acrylic_nails')} />
          <SpecialToggle active={hasWound} onClick={() => setHasWound(!hasWound)} label={t('wound_cast')} />
        </div>

        <div className="flex items-center space-x-4">
          <button 
            onClick={handleBack}
            disabled={currentStep === 0}
            className="p-4 bg-gray-50 text-emerald-900 rounded-2xl disabled:opacity-30"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <button 
            onClick={handleNext}
            disabled={!isStepComplete()}
            className={cn(
              "flex-1 py-4 rounded-2xl font-bold flex items-center justify-center space-x-2 transition-all",
              isStepComplete() ? "bg-emerald-600 text-white shadow-lg shadow-emerald-200" : "bg-gray-100 text-gray-400"
            )}
          >
            <span>{currentStep === STEPS.length - 1 ? t('finish_ghusl') : t('next')}</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </motion.div>
  );
};

const SpecialToggle = ({ active, onClick, label }: { active: boolean, onClick: () => void, label: string }) => (
  <button 
    onClick={onClick}
    className={cn(
      "px-4 py-2 rounded-full text-[10px] font-bold uppercase tracking-widest whitespace-nowrap transition-all",
      active ? "bg-emerald-600 text-white" : "bg-gray-50 text-gray-400 border border-black/5"
    )}
  >
    {label}
  </button>
);
