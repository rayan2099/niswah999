/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  ChevronRight, 
  ChevronLeft, 
  Check, 
  Info, 
  Lock, 
  Bell, 
  Star, 
  Calendar as CalendarIcon,
  Globe,
  BookOpen,
  Target,
  Activity,
  ShieldCheck,
  Zap,
  Sparkles,
  Search,
  MapPin,
  CheckCircle2,
  X,
  Navigation
} from 'lucide-react';
import { format, subDays, addDays } from 'date-fns';
import * as api from '../api/index.ts';
import { DBUser } from '../api/db-types.ts';
import { Madhhab } from '../logic/types.ts';
import { popularCities } from '../logic/constants.ts';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { cn } from '../utils/cn.ts';

// --- TYPES ---

type Language = 'ar' | 'en';

interface OnboardingData {
  language: Language;
  madhhab: Madhhab | null;
  goal_flags: string[];
  last_period_date: string | null;
  avg_cycle_length: number | null;
  avg_haid_duration: number;
  conditions: string[];
  privacy_setup: {
    method: 'biometric' | 'pin' | 'skip';
    anonymous_mode: boolean;
  };
  notification_prefs: Record<string, boolean>;
  location: {
    city: string;
    country: string;
    cityAr: string;
    countryAr: string;
    lat?: number;
    lon?: number;
  };
}

const INITIAL_DATA: OnboardingData = {
  language: 'en',
  madhhab: null,
  goal_flags: [],
  last_period_date: null,
  avg_cycle_length: null,
  avg_haid_duration: 5,
  conditions: [],
  privacy_setup: {
    method: 'skip',
    anonymous_mode: false,
  },
  notification_prefs: {
    prayer_updates: true,
    period_prediction: true,
    ovulation_alert: true,
    ghusl_reminder: true,
    daily_insights: true,
    ramadan_qadha: true,
  },
  location: {
    city: '',
    country: '',
    cityAr: '',
    countryAr: '',
    lat: 0,
    lon: 0,
  },
};

// --- COMPONENTS ---

const ProgressBar = ({ current, total }: { current: number; total: number }) => {
  const progress = (current / total) * 100;
  const { isRTL } = useTranslation();
  return (
    <div className="fixed top-0 left-0 right-0 h-1.5 bg-black/5 z-50">
      <motion.div 
        className="h-full bg-rose-300"
        initial={{ width: 0 }}
        animate={{ width: `${progress}%` }}
        style={{ transformOrigin: isRTL ? 'right' : 'left' }}
        transition={{ type: 'spring', stiffness: 50, damping: 20 }}
      />
    </div>
  );
};

// --- SCREENS ---

const Screen1Splash = ({ onNext }: { onNext: () => void }) => {
  const { t } = useTranslation();
  useEffect(() => {
    const timer = setTimeout(onNext, 2500);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="flex flex-col items-center justify-center space-y-8">
      <div className="flex flex-col items-center justify-center space-y-4">
        <motion.h1 
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.8, ease: 'easeOut' }}
          className="text-5xl font-serif font-bold text-rose-800"
        >
          Niswah
        </motion.h1>
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.8 }}
          className="text-rose-400 font-medium tracking-widest uppercase text-xs text-center"
        >
          {t('splash_tagline')}
        </motion.p>
      </div>

      <motion.button
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 1.2, duration: 0.6 }}
        onClick={onNext}
        className="px-8 py-3 bg-rose-600 text-white rounded-full font-bold shadow-lg shadow-rose-200 hover:bg-rose-700 transition-colors"
      >
        {t('get_started')}
      </motion.button>
    </div>
  );
};

const Screen2Language = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, setLanguage, isRTL } = useTranslation();
  const languages: { code: Language; label: string; native: string }[] = [
    { code: 'ar', label: t('arabic'), native: 'العربية' },
    { code: 'en', label: t('english'), native: 'English' },
  ];

  const handleSelect = (code: Language) => {
    update({ language: code });
    setLanguage(code);
  };

  return (
    <div className="w-full space-y-8">
      <h2 className="text-3xl font-serif font-bold text-center">{t('choose_language')}</h2>
      <div className="grid grid-cols-2 gap-4">
        {languages.map((lang) => (
          <motion.button
            key={lang.code}
            whileTap={{ scale: 1.04 }}
            onClick={() => handleSelect(lang.code)}
            className={cn(
              "p-6 rounded-2xl border-2 transition-all flex flex-col items-center justify-center space-y-2 relative",
              data.language === lang.code 
                ? "border-rose-300 bg-rose-50 text-rose-800 shadow-sm" 
                : "border-black/5 bg-white text-gray-400 hover:border-rose-100"
            )}
          >
            <span className="text-lg font-bold">{lang.native}</span>
            <span className="text-xs opacity-60">{lang.label}</span>
            {data.language === lang.code && (
              <motion.div layoutId="lang-check" className={cn("absolute top-2", isRTL ? "left-2" : "right-2")}>
                <Check className="w-4 h-4 text-rose-400" />
              </motion.div>
            )}
          </motion.button>
        ))}
      </div>
      <button 
        onClick={onNext}
        className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100 flex items-center justify-center space-x-2"
      >
        <span>{t('continue')}</span>
        <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
      </button>
    </div>
  );
};

const Screen3Madhhab = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const [showInfo, setShowInfo] = useState(false);
  const madhhabs: { id: Madhhab; label: string; rule: string }[] = [
    { id: 'HANAFI', label: t('hanafi'), rule: t('hanafi_rule_onboarding') },
    { id: 'MALIKI', label: t('maliki'), rule: t('maliki_rule_onboarding') },
    { id: 'SHAFII', label: t('shafi'), rule: t('shafii_rule_onboarding') },
    { id: 'HANBALI', label: t('hanbali'), rule: t('hanbali_rule_onboarding') },
  ];

  return (
    <div className="w-full space-y-6">
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-serif font-bold">{t('madhhab_question')}</h2>
        <p className="text-sm text-gray-500">{t('madhhab_desc')}</p>
      </div>
      
      <div className="grid grid-cols-2 gap-4">
        {madhhabs.map((m) => (
          <motion.button
            key={m.id}
            whileTap={{ scale: 1.04 }}
            onClick={() => update({ madhhab: m.id })}
            className={cn(
              "p-5 rounded-2xl border-2 transition-all text-left flex flex-col justify-between h-32",
              data.madhhab === m.id 
                ? "border-rose-300 bg-rose-50 shadow-sm" 
                : "border-black/5 bg-white hover:border-rose-100"
            )}
          >
            <span className={cn("text-lg font-bold", data.madhhab === m.id ? "text-rose-800" : "text-gray-700")}>{m.label}</span>
            <span className="text-[10px] leading-tight text-gray-400 uppercase tracking-wider font-semibold">{m.rule}</span>
          </motion.button>
        ))}
      </div>

      <button 
        onClick={() => setShowInfo(true)}
        className="w-full flex items-center justify-center text-rose-400 text-sm font-medium hover:underline"
      >
        <Info className={cn("w-4 h-4", isRTL ? "ml-2" : "mr-2")} /> {t('not_sure_madhhab')}
      </button>

      <button 
        disabled={!data.madhhab}
        onClick={onNext}
        className={cn(
          "w-full py-4 rounded-2xl font-bold flex items-center justify-center transition-all space-x-2",
          data.madhhab 
            ? "bg-rose-400 text-white shadow-lg shadow-rose-100" 
            : "bg-gray-100 text-gray-400 cursor-not-allowed"
        )}
      >
        <span>{t('continue')}</span>
        <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
      </button>

      <AnimatePresence>
        {showInfo && (
          <motion.div 
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            className="fixed inset-0 z-50 bg-black/40 flex items-end"
            onClick={() => setShowInfo(false)}
          >
            <motion.div 
              className="bg-white w-full rounded-t-[32px] p-8 space-y-6 max-h-[80vh] overflow-y-auto"
              onClick={e => e.stopPropagation()}
            >
              <div className="w-12 h-1.5 bg-gray-200 rounded-full mx-auto" />
              <h3 className="text-xl font-bold">{t('about_madhhabs')}</h3>
              <div className="space-y-4 text-sm text-gray-600 leading-relaxed">
                <p><strong>{t('hanafi')}:</strong> {t('hanafi_summary')}</p>
                <p><strong>{t('maliki')}:</strong> {t('maliki_summary')}</p>
                <p><strong>{t('shafi')} & {t('hanbali')}:</strong> {t('shafii_summary')}</p>
                <p>{t('scholar_consult_note')}</p>
              </div>
              <button 
                onClick={() => setShowInfo(false)}
                className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold"
              >
                {t('got_it')}
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

const Screen4Goals = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const goals = [
    t('goal_track_cycle'),
    t('goal_understand_fiqh'),
    t('goal_get_pregnant'),
    t('goal_postpartum'),
    t('goal_irregular_bleeding'),
    t('goal_spiritual_wellness'),
    t('goal_general_health')
  ];

  const toggleGoal = (goal: string) => {
    const next = data.goal_flags.includes(goal)
      ? data.goal_flags.filter(g => g !== goal)
      : [...data.goal_flags, goal];
    update({ goal_flags: next });
  };

  return (
    <div className="w-full space-y-8">
      <div className="text-center space-y-2">
        <h2 className="text-3xl font-serif font-bold">{t('goals_question')}</h2>
        <p className="text-sm text-gray-500">{t('select_all_apply')}</p>
      </div>

      <div className="flex flex-wrap gap-3 justify-center">
        {goals.map((goal) => (
          <motion.button
            key={goal}
            whileTap={{ scale: 0.95 }}
            onClick={() => toggleGoal(goal)}
            className={cn(
              "px-5 py-3 rounded-full border-2 transition-all text-sm font-medium",
              data.goal_flags.includes(goal)
                ? "border-rose-300 bg-rose-300 text-white shadow-md"
                : "border-black/5 bg-white text-gray-600 hover:border-rose-100"
            )}
          >
            {goal}
          </motion.button>
        ))}
      </div>

      <button 
        disabled={data.goal_flags.length === 0}
        onClick={onNext}
        className={cn(
          "w-full py-4 rounded-2xl font-bold flex items-center justify-center transition-all space-x-2",
          data.goal_flags.length > 0
            ? "bg-rose-400 text-white shadow-lg shadow-rose-100" 
            : "bg-gray-100 text-gray-400 cursor-not-allowed"
        )}
      >
        <span>{t('continue')}</span>
        <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
      </button>
    </div>
  );
};

const ScreenLocation = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [isFocused, setIsFocused] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isDetecting, setIsDetecting] = useState(false);

  useEffect(() => {
    const searchCities = async () => {
      const trimmedQuery = query.trim().replace(/[،,.;]$/, '');
      if (trimmedQuery.length >= 2) {
        // First check local popular cities
        const localFiltered = popularCities.filter(c => 
          c.name.includes(trimmedQuery) || 
          c.nameEn.toLowerCase().includes(trimmedQuery.toLowerCase()) ||
          c.country.includes(trimmedQuery) ||
          c.countryEn.toLowerCase().includes(trimmedQuery.toLowerCase())
        );

        // If we have local results, show them first
        if (localFiltered.length > 0) {
          setSuggestions(localFiltered.slice(0, 6));
          // If it's a very specific match, we might not need API search
          if (localFiltered.some(c => c.name === trimmedQuery || c.nameEn.toLowerCase() === trimmedQuery.toLowerCase())) {
            return;
          }
        }

        // Try external search for more results
        setIsLoading(true);
        try {
          const response = await fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(trimmedQuery)}&addressdetails=1&limit=5&accept-language=${isRTL ? 'ar' : 'en'}`);
          const results = await response.json();
          
          const apiSuggestions = results.map((item: any) => ({
            name: item.address.city || item.address.town || item.address.village || item.display_name.split(',')[0],
            nameEn: item.display_name.split(',')[0], // Fallback
            country: item.address.country,
            countryEn: item.address.country, // Fallback
            lat: item.lat,
            lon: item.lon
          }));
          
          // Combine local and API suggestions, avoiding duplicates if possible
          setSuggestions(prev => {
            const combined = [...localFiltered];
            apiSuggestions.forEach((api: any) => {
              if (!combined.some(c => c.name === api.name)) {
                combined.push(api);
              }
            });
            return combined.slice(0, 8);
          });
        } catch (error) {
          console.error("Search error:", error);
        } finally {
          setIsLoading(false);
        }
      } else {
        setSuggestions([]);
      }
    };

    const timeoutId = setTimeout(searchCities, 500);
    return () => clearTimeout(timeoutId);
  }, [query, isRTL]);

  const handleDetectLocation = () => {
    if (!navigator.geolocation) {
      alert("Geolocation is not supported by your browser");
      return;
    }

    setIsDetecting(true);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          const { latitude, longitude } = position.coords;
          const response = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&addressdetails=1&accept-language=${isRTL ? 'ar' : 'en'}`);
          const result = await response.json();
          
          if (result.address) {
            const city = result.address.city || result.address.town || result.address.village || result.address.state;
            const country = result.address.country;
            
            update({
              location: {
                city: city,
                country: country,
                cityAr: city,
                countryAr: country,
                lat: latitude,
                lon: longitude
              }
            });
            onNext();
          }
        } catch (error) {
          console.error("Reverse geocoding error:", error);
          alert("Could not determine your location name. Please search manually.");
        } finally {
          setIsDetecting(false);
        }
      },
      (error) => {
        console.error("Geolocation error:", error);
        setIsDetecting(false);
        alert("Could not access your location. Please search manually.");
      }
    );
  };

  const handleSelect = (city: any) => {
    update({
      location: {
        city: city.nameEn || city.name,
        country: city.countryEn || city.country,
        cityAr: city.name,
        countryAr: city.country,
        lat: city.lat,
        lon: city.lon
      }
    });
    onNext();
  };

  return (
    <div className="w-full space-y-8">
      <div className="text-center space-y-2">
        <h2 className="text-3xl font-serif font-bold">{t('location_title')}</h2>
        <p className="text-sm text-gray-500">{t('location_desc')}</p>
      </div>

      <div className="space-y-4 relative">
        <button
          onClick={handleDetectLocation}
          disabled={isDetecting}
          className="w-full py-4 bg-rose-50 text-rose-600 rounded-2xl font-bold flex items-center justify-center space-x-2 hover:bg-rose-100 transition-all"
        >
          {isDetecting ? (
            <div className="w-5 h-5 border-2 border-rose-600 border-t-transparent rounded-full animate-spin" />
          ) : (
            <Navigation className="w-5 h-5" />
          )}
          <span>{isDetecting ? t('detecting' as any) : t('use_current_location' as any)}</span>
        </button>

        <div className="relative">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-300" />
          <input 
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onFocus={() => setIsFocused(true)}
            placeholder={t('enter_city_name')}
            className="w-full pl-12 pr-4 py-4 bg-white border-2 border-black/5 rounded-2xl text-sm focus:border-rose-300 outline-none transition-all text-right"
            dir="rtl"
          />
          {isLoading && (
            <div className="absolute right-12 top-1/2 -translate-y-1/2">
              <div className="w-4 h-4 border-2 border-rose-300 border-t-transparent rounded-full animate-spin" />
            </div>
          )}
          {query && (
            <button 
              onClick={() => setQuery('')}
              className="absolute right-4 top-1/2 -translate-y-1/2 p-1 hover:bg-gray-100 rounded-full"
            >
              <X className="w-4 h-4 text-gray-400" />
            </button>
          )}
        </div>

        <AnimatePresence>
          {isFocused && query.trim().length >= 2 && !isLoading && suggestions.length === 0 && (
            <motion.div 
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="absolute z-50 left-0 right-0 top-full mt-2 bg-white rounded-2xl border border-black/5 shadow-xl p-4 text-center text-gray-500 text-sm"
            >
              {t('no_results')}
            </motion.div>
          )}

          {isFocused && suggestions.length > 0 && (
            <motion.div 
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="absolute z-50 left-0 right-0 top-full mt-2 bg-white rounded-2xl border border-black/5 shadow-xl overflow-hidden"
            >
              {suggestions.map((city, i) => (
                <button
                  key={i}
                  onClick={() => handleSelect(city)}
                  className="w-full p-4 hover:bg-gray-50 flex items-center justify-between border-b border-gray-50 last:border-0 text-right"
                  dir="rtl"
                >
                  <div className="flex flex-col items-start">
                    <span className="text-sm font-bold text-gray-800">{city.name}</span>
                    <span className="text-[10px] text-gray-400">{city.country}</span>
                  </div>
                  <MapPin className="w-4 h-4 text-gray-300" />
                </button>
              ))}
            </motion.div>
          )}
        </AnimatePresence>

        {/* Popular Cities Quick Select */}
        {!query && (
          <div className="space-y-3 pt-4">
            <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('popular_cities' as any)}</h3>
            <div className="grid grid-cols-2 gap-2">
              {popularCities.slice(0, 6).map((city, i) => (
                <button
                  key={i}
                  onClick={() => handleSelect(city)}
                  className="p-3 bg-white border border-black/5 rounded-xl text-xs font-bold text-gray-700 hover:border-rose-200 hover:bg-rose-50 transition-all text-right"
                  dir="rtl"
                >
                  {city.name}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      <button 
        onClick={onNext}
        className="w-full py-4 text-gray-400 text-sm font-medium hover:text-rose-400"
      >
        {t('skip_for_now')}
      </button>
    </div>
  );
};

const Screen5LastPeriod = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const [selectedDate, setSelectedDate] = useState<Date | null>(data.last_period_date ? new Date(data.last_period_date) : null);

  const handleSelect = (date: Date) => {
    setSelectedDate(date);
    update({ last_period_date: date.toISOString() });
  };

  const handleNotSure = () => {
    setSelectedDate(null);
    update({ last_period_date: null });
    onNext();
  };

  const weekDays = isRTL 
    ? [t('sat'), t('fri'), t('thu'), t('wed'), t('tue'), t('mon'), t('sun')]
    : [t('sun'), t('mon'), t('tue'), t('wed'), t('thu'), t('fri'), t('sat')];

  return (
    <div className="w-full space-y-8">
      <h2 className="text-3xl font-serif font-bold text-center">{t('last_period_question')}</h2>
      
      <div className="bg-white rounded-3xl p-6 shadow-xl shadow-black/5 border border-black/5">
        <div className="grid grid-cols-7 gap-2 text-center mb-4">
          {weekDays.map(d => (
            <span key={d} className="text-[10px] font-bold text-gray-300 uppercase">{d}</span>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-2">
          {Array.from({ length: 31 }).map((_, i) => {
            const date = subDays(new Date(), 30 - i);
            const isSelected = selectedDate && format(date, 'yyyy-MM-dd') === format(selectedDate, 'yyyy-MM-dd');
            const isToday = format(date, 'yyyy-MM-dd') === format(new Date(), 'yyyy-MM-dd');
            
            return (
              <button
                key={i}
                onClick={() => handleSelect(date)}
                className={cn(
                  "aspect-square rounded-full text-sm font-bold flex items-center justify-center transition-all",
                  isSelected ? "bg-rose-300 text-white" : isToday ? "text-rose-400 ring-1 ring-rose-400" : "text-gray-700 hover:bg-rose-50"
                )}
              >
                {date.getDate()}
              </button>
            );
          })}
        </div>
      </div>

      <div className="space-y-4">
        <button 
          disabled={!selectedDate}
          onClick={onNext}
          className={cn(
            "w-full py-4 rounded-2xl font-bold flex items-center justify-center transition-all space-x-2",
            selectedDate ? "bg-rose-400 text-white shadow-lg shadow-rose-100" : "bg-gray-100 text-gray-400 cursor-not-allowed"
          )}
        >
          <span>{t('continue')}</span>
          <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
        </button>
        <button 
          onClick={handleNotSure}
          className="w-full text-center text-gray-400 text-sm font-medium hover:text-rose-400"
        >
          {t('not_sure')}
        </button>
      </div>
    </div>
  );
};

const Screen6CycleLength = ({ onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  return (
    <div className="w-full space-y-12">
      <div className="text-center space-y-2">
        <h2 className="text-3xl font-serif font-bold">
          {isRTL ? 'يُحسب طول دورتكِ من سجلاتكِ' : 'Your cycle length is calculated from your logs'}
        </h2>
        <p className="text-sm text-gray-500">
          {isRTL
            ? 'بعد تسجيل بدايتَي حيض، ستحسب نسوة متوسطكِ الشخصي دون افتراضات.'
            : 'After two logged Haid starts, Niswah will calculate your personal average without assumptions.'}
        </p>
      </div>

      <div className="space-y-4">
        <button 
          onClick={onNext}
          className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100 flex items-center justify-center space-x-2"
        >
          <span>{t('continue')}</span>
          <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
        </button>
      </div>
    </div>
  );
};

const Screen7PeriodDuration = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const maxDays = data.madhhab === 'HANAFI' ? 10 : 15;
  
  return (
    <div className="w-full space-y-12">
      <h2 className="text-3xl font-serif font-bold text-center">{t('period_duration_question')}</h2>

      <div className="flex flex-col items-center space-y-8">
        <motion.div 
          key={data.avg_haid_duration}
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          className="text-7xl font-serif font-bold text-rose-400"
        >
          {data.avg_haid_duration} <span className="text-2xl text-rose-800/40">{t('days')}</span>
        </motion.div>

        <input 
          type="range" 
          min="2" 
          max={maxDays} 
          value={data.avg_haid_duration}
          onChange={(e) => update({ avg_haid_duration: parseInt(e.target.value) })}
          className="w-full h-2 bg-rose-50 rounded-lg appearance-none cursor-pointer accent-rose-400"
        />
        
        <div className="text-center">
          <p className="text-xs font-bold text-rose-800/40 uppercase tracking-widest">
            {data.madhhab === 'HANAFI' ? t('hanafi_max_10') : t('other_max_15')}
          </p>
        </div>
      </div>

      <div className="space-y-4">
        <button 
          onClick={onNext}
          className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100 flex items-center justify-center space-x-2"
        >
          <span>{t('continue')}</span>
          <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
        </button>
        <button 
          onClick={() => { update({ avg_haid_duration: 5 }); onNext(); }}
          className="w-full text-center text-gray-400 text-sm font-medium hover:text-rose-400"
        >
          {t('not_sure')}
        </button>
      </div>
    </div>
  );
};

const Screen8Conditions = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const conditions = [
    t('cond_pcos'),
    t('cond_endo'),
    t('cond_thyroid'),
    t('cond_fibroids'),
    t('cond_none'),
    t('cond_prefer_not_to_say')
  ];

  const toggleCondition = (c: string) => {
    if (c === t('cond_none') || c === t('cond_prefer_not_to_say')) {
      update({ conditions: [c] });
    } else {
      const filtered = data.conditions.filter(item => item !== t('cond_none') && item !== t('cond_prefer_not_to_say'));
      const next = filtered.includes(c) ? filtered.filter(item => item !== c) : [...filtered, c];
      update({ conditions: next });
    }
  };

  return (
    <div className="w-full space-y-8">
      <div className="text-center space-y-2">
        <h2 className="text-3xl font-serif font-bold">{t('conditions_question')}</h2>
        <p className="text-sm text-gray-500">{t('conditions_desc')}</p>
      </div>

      <div className="flex flex-wrap gap-3 justify-center">
        {conditions.map((c) => (
          <motion.button
            key={c}
            whileTap={{ scale: 0.95 }}
            onClick={() => toggleCondition(c)}
            className={cn(
              "px-5 py-3 rounded-full border-2 transition-all text-sm font-medium",
              data.conditions.includes(c)
                ? "border-rose-300 bg-rose-300 text-white shadow-md"
                : "border-black/5 bg-white text-gray-600 hover:border-rose-100"
            )}
          >
            {c}
          </motion.button>
        ))}
      </div>

      <button 
        disabled={data.conditions.length === 0}
        onClick={onNext}
        className={cn(
          "w-full py-4 rounded-2xl font-bold flex items-center justify-center transition-all space-x-2",
          data.conditions.length > 0 ? "bg-rose-400 text-white shadow-lg shadow-rose-100" : "bg-gray-100 text-gray-400 cursor-not-allowed"
        )}
      >
        <span>{t('continue')}</span>
        <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
      </button>
    </div>
  );
};

const Screen9Privacy = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  return (
    <div className="w-full space-y-6">
      <h2 className="text-3xl font-serif font-bold text-center">{t('privacy_title')}</h2>

      <div className="space-y-3">
        {[
          { id: 'biometric', label: t('face_id_touch_id'), icon: ShieldCheck },
          { id: 'pin', label: t('pin_code'), icon: Lock },
          { id: 'skip', label: t('skip_for_now'), icon: ChevronRight },
        ].map((opt) => (
          <motion.button
            key={opt.id}
            whileTap={{ scale: 0.98 }}
            onClick={() => update({ privacy_setup: { ...data.privacy_setup, method: opt.id as any } })}
            className={cn(
              "w-full p-5 rounded-2xl border-2 flex items-center justify-between transition-all",
              data.privacy_setup.method === opt.id ? "border-rose-300 bg-rose-50" : "border-black/5 bg-white"
            )}
          >
            <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-4" : "space-x-4")}>
              <opt.icon className={cn("w-6 h-6", data.privacy_setup.method === opt.id ? "text-rose-400" : "text-gray-400", isRTL && opt.id === 'skip' && "rotate-180")} />
              <span className="font-bold">{opt.label}</span>
            </div>
            {data.privacy_setup.method === opt.id && <Check className="w-5 h-5 text-rose-400" />}
          </motion.button>
        ))}
      </div>

      <div className="p-6 rounded-3xl bg-rose-800 text-white space-y-4">
        <div className={cn("flex items-center justify-between", isRTL && "flex-row-reverse")}>
          <div className={cn("flex items-center", isRTL ? "space-x-reverse space-x-3" : "space-x-3")}>
            <Zap className="w-6 h-6 text-rose-300" />
            <span className="font-bold">{t('anonymous_mode')}</span>
          </div>
          <button 
            onClick={() => update({ privacy_setup: { ...data.privacy_setup, anonymous_mode: !data.privacy_setup.anonymous_mode } })}
            className={cn(
              "w-12 h-6 rounded-full transition-all relative",
              data.privacy_setup.anonymous_mode ? "bg-rose-300" : "bg-rose-700"
            )}
          >
            <motion.div 
              animate={{ x: data.privacy_setup.anonymous_mode ? (isRTL ? -24 : 24) : (isRTL ? -4 : 4) }}
              className="absolute top-1 w-4 h-4 bg-white rounded-full"
              style={{ [isRTL ? 'right' : 'left']: 0 }}
            />
          </button>
        </div>
        <p className="text-xs text-rose-50/60 leading-relaxed">
          {t('anonymous_mode_desc')}
        </p>
      </div>

      <button 
        onClick={onNext}
        className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100 flex items-center justify-center space-x-2"
      >
        <span>{t('continue')}</span>
        <ChevronRight className={cn("w-5 h-5", isRTL && "rotate-180")} />
      </button>
    </div>
  );
};

const Screen10Notifications = ({ data, update, onNext }: { data: OnboardingData; update: (d: Partial<OnboardingData>) => void; onNext: () => void }) => {
  const { t, isRTL } = useTranslation();
  const options = [
    { id: 'prayer_updates', label: t('prayer_updates'), sub: t('prayer_updates_sub') },
    { id: 'period_prediction', label: t('period_prediction'), sub: t('period_prediction_sub') },
    { id: 'ovulation_alert', label: t('ovulation_alert'), sub: t('ovulation_alert_sub') },
    { id: 'ghusl_reminder', label: t('ghusl_reminder'), sub: t('ghusl_reminder_sub') },
    { id: 'daily_insights', label: t('daily_insights_notif'), sub: t('daily_insights_sub') },
    { id: 'ramadan_qadha', label: t('ramadan_qadha_notif'), sub: t('ramadan_qadha_sub') },
  ];

  const toggle = (id: string) => {
    update({ notification_prefs: { ...data.notification_prefs, [id]: !data.notification_prefs[id] } });
  };

  const enableAll = () => {
    const all = Object.keys(data.notification_prefs).reduce((acc, key) => ({ ...acc, [key]: true }), {});
    update({ notification_prefs: all as any });
    onNext();
  };

  return (
    <div className="w-full space-y-6">
      <h2 className="text-3xl font-serif font-bold text-center">{t('notifications_title')}</h2>

      <div className="space-y-4 max-h-[50vh] overflow-y-auto pr-2 custom-scrollbar">
        {options.map((opt) => (
          <div key={opt.id} className={cn("flex items-center justify-between p-2", isRTL && "flex-row-reverse")}>
            <div className={cn("flex-1", isRTL ? "text-right" : "text-left")}>
              <p className="font-bold text-sm">{opt.label}</p>
              <p className="text-[10px] text-gray-400">{opt.sub}</p>
            </div>
            <button 
              onClick={() => toggle(opt.id)}
              className={cn(
                "w-10 h-5 rounded-full transition-all relative",
                data.notification_prefs[opt.id] ? "bg-rose-300" : "bg-gray-200"
              )}
            >
              <motion.div 
                animate={{ x: data.notification_prefs[opt.id] ? (isRTL ? -20 : 20) : (isRTL ? -4 : 4) }}
                className="absolute top-1 w-3 h-3 bg-white rounded-full"
                style={{ [isRTL ? 'right' : 'left']: 0 }}
              />
            </button>
          </div>
        ))}
      </div>

      <div className="space-y-4 pt-4">
        <button 
          onClick={enableAll}
          className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100"
        >
          {t('enable_recommended')}
        </button>
        <button 
          onClick={onNext}
          className="w-full text-center text-gray-400 text-sm font-medium hover:text-rose-400"
        >
          {t('choose_own')}
        </button>
      </div>
    </div>
  );
};

const Screen11Welcome = ({ onComplete, isCompleting }: { onComplete: () => void; isCompleting: boolean }) => {
  const { t, isRTL } = useTranslation();
  return (
    <div className="w-full space-y-8 text-center">
      <div className="w-20 h-20 bg-rose-50 rounded-full flex items-center justify-center mx-auto mb-4">
        <Sparkles className="w-10 h-10 text-rose-400" />
      </div>
      <div className="space-y-2">
        <h2 className="text-3xl font-serif font-bold text-rose-800">{t('welcome_to_plus')}</h2>
        <p className="text-sm text-gray-500 leading-relaxed">
          {t('freemium_desc')}
        </p>
      </div>

      <div className="bg-rose-50 rounded-[32px] p-6 border border-rose-100 space-y-4">
        <h3 className="text-[10px] font-bold text-rose-400 uppercase tracking-widest">{t('included_features')}</h3>
        <div className="grid grid-cols-2 gap-3">
          {[
            { icon: Sparkles, label: t('feat_nisa_ai') },
            { icon: Activity, label: t('feat_insights') },
            { icon: BookOpen, label: t('feat_journeys') },
            { icon: ShieldCheck, label: t('feat_privacy') }
          ].map((feat, i) => (
            <div key={i} className="flex items-center space-x-2 rtl:space-x-reverse text-left rtl:text-right">
              <feat.icon className="w-4 h-4 text-rose-400" />
              <span className="text-[10px] font-bold text-rose-800">{feat.label}</span>
            </div>
          ))}
        </div>
      </div>

      <button 
        onClick={onComplete}
        disabled={isCompleting}
        className={cn(
          "w-full py-5 text-white rounded-2xl font-bold shadow-xl transition-all flex items-center justify-center",
          isCompleting ? "bg-rose-400 cursor-not-allowed" : "bg-rose-600 hover:bg-rose-700 shadow-rose-200"
        )}
      >
        {isCompleting ? (
          <div className="w-6 h-6 border-2 border-white border-t-transparent rounded-full animate-spin" />
        ) : (
          t('get_started')
        )}
      </button>
    </div>
  );
};

// --- MAIN COMPONENT ---

export const Onboarding = ({ onFinish }: { onFinish: (userData: DBUser) => void }) => {
  const { isRTL, t } = useTranslation();
  const [step, setStep] = useState(1);
  const [data, setData] = useState<OnboardingData>(INITIAL_DATA);
  const [direction, setDirection] = useState(1);
  const [isCompleting, setIsCompleting] = useState(false);

  const updateData = (partial: Partial<OnboardingData>) => {
    setData(prev => ({ ...prev, ...partial }));
  };

  const nextStep = () => {
    setDirection(1);
    setStep(s => Math.min(s + 1, 12));
  };

  const prevStep = () => {
    if (step === 3 && !data.madhhab) return; // Cannot go back from Screen 3 without selection
    setDirection(-1);
    setStep(s => Math.max(s - 1, 1));
  };

  const complete = async () => {
    try {
      setIsCompleting(true);
      // Save to Supabase
      const { data: savedUser, error: userError } = await api.upsertUser({
        madhhab: data.madhhab as Madhhab,
        language: data.language,
        avg_cycle_length: data.avg_cycle_length,
        avg_haid_duration: data.avg_haid_duration,
        goal_flags: data.goal_flags,
        conditions: data.conditions,
        notification_prefs: data.notification_prefs,
        anonymous_mode: data.privacy_setup.anonymous_mode,
        premium_status: true,
        prayerCity: data.location.city,
        prayerCountry: data.location.country,
        prayerCityAr: data.location.cityAr,
        prayerCountryAr: data.location.countryAr,
        prayerLat: data.location.lat,
        prayerLon: data.location.lon,
        manual_prayer_offsets: { fajr: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 0 }
      });

      if (userError) {
        throw new Error(userError);
      }

      if (data.last_period_date) {
        const { error: entryError } = await api.logCycleEntry({
          date: data.last_period_date.split('T')[0],
          time_logged: data.last_period_date,
          fiqh_state: 'HAID'
        });
        if (entryError) {
          console.error("Failed to log cycle entry", entryError);
        }
      }
      if (savedUser) {
        onFinish(savedUser);
      } else {
        // Fallback if savedUser is null for some reason but no error was thrown
        const { data: freshUser } = await api.getUser();
        if (freshUser) onFinish(freshUser);
        else window.location.reload();
      }
    } catch (err) {
      console.error("Failed to save onboarding data", err);
      alert(t('error_saving_profile') || "Failed to save your profile. Please check your internet connection and try again.");
    } finally {
      setIsCompleting(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-[#FDFCFB] flex flex-col overflow-hidden" dir={isRTL ? 'rtl' : 'ltr'}>
      {step > 1 && <ProgressBar current={step} total={12} />}
      
      {step > 2 && step < 12 && (
        <button 
          onClick={prevStep}
          className={cn(
            "absolute top-8 z-50 p-2 text-gray-400 hover:text-rose-400",
            isRTL ? "right-6" : "left-6"
          )}
        >
          <ChevronLeft className={cn("w-6 h-6", isRTL && "rotate-180")} />
        </button>
      )}

      <AnimatePresence mode="wait" custom={direction}>
        <motion.div
          key={step}
          custom={direction}
          initial={{ x: direction > 0 ? (isRTL ? -100 : 100) : (isRTL ? 100 : -100), opacity: 0, scale: 0.96 }}
          animate={{ x: 0, opacity: 1, scale: 1 }}
          exit={{ x: direction > 0 ? (isRTL ? 100 : -100) : (isRTL ? -100 : 100), opacity: 0, scale: 0.96 }}
          transition={{ duration: 0.35, ease: 'easeOut' }}
          className="flex-1 flex flex-col items-center justify-center p-6 w-full max-w-md mx-auto h-full"
        >
          {step === 1 && <Screen1Splash onNext={nextStep} />}
          {step === 2 && <Screen2Language data={data} update={updateData} onNext={nextStep} />}
          {step === 3 && <Screen3Madhhab data={data} update={updateData} onNext={nextStep} />}
          {step === 4 && <Screen4Goals data={data} update={updateData} onNext={nextStep} />}
          {step === 5 && <ScreenLocation data={data} update={updateData} onNext={nextStep} />}
          {step === 6 && <Screen5LastPeriod data={data} update={updateData} onNext={nextStep} />}
          {step === 7 && <Screen6CycleLength data={data} update={updateData} onNext={nextStep} />}
          {step === 8 && <Screen7PeriodDuration data={data} update={updateData} onNext={nextStep} />}
          {step === 9 && <Screen8Conditions data={data} update={updateData} onNext={nextStep} />}
          {step === 10 && <Screen9Privacy data={data} update={updateData} onNext={nextStep} />}
          {step === 11 && <Screen10Notifications data={data} update={updateData} onNext={nextStep} />}
          {step === 12 && <Screen11Welcome onComplete={complete} isCompleting={isCompleting} />}
        </motion.div>
      </AnimatePresence>
    </div>
  );
};
