/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  User, 
  Shield, 
  Bell, 
  Globe, 
  CreditCard, 
  ChevronRight, 
  LogOut, 
  Trash2, 
  Download, 
  Lock, 
  EyeOff, 
  Fingerprint,
  Check,
  AlertCircle,
  Sparkles,
  BookOpen,
  Calendar,
  Users,
  Stethoscope,
  X,
  Share2,
  Heart,
  Star,
  Search,
  MapPin,
  CheckCircle2
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { format } from 'date-fns';
import * as api from '../api/index.ts';
import { Madhhab } from '../logic/types.ts';
import { popularCities } from '../logic/constants.ts';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { useCycleData } from '../contexts/CycleContext.tsx';
import { Paywall } from './Paywall.tsx';
import { NotificationService } from '../services/NotificationService.ts';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface ProfileProps {
  onOpenGhusl: () => void;
  onOpenJourneys: () => void;
  onOpenAdah: () => void;
}

// --- CITY SEARCH COMPONENT ---

const CitySearch = ({ 
  currentCity, 
  currentCountry, 
  currentCityAr,
  onSelect 
}: { 
  currentCity: string; 
  currentCountry: string; 
  currentCityAr: string;
  onSelect: (city: any) => void 
}) => {
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [isFocused, setIsFocused] = useState(false);
  const [isEditing, setIsEditing] = useState(!currentCity);
  const [isLoading, setIsLoading] = useState(false);
  const [isDetecting, setIsDetecting] = useState(false);
  const { t, language } = useTranslation();
  const isRTL = language === 'ar';

  const detectLocation = async () => {
    if (!navigator.geolocation) {
      alert(t('geo_not_supported'));
      return;
    }

    setIsDetecting(true);
    navigator.geolocation.getCurrentPosition(async (position) => {
      try {
        const { latitude, longitude } = position.coords;
        const response = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&addressdetails=1&accept-language=${isRTL ? 'ar' : 'en'}`);
        const data = await response.json();
        
        if (data.address) {
          const city = data.address.city || data.address.town || data.address.village || data.address.state;
          const country = data.address.country;
          
          onSelect({
            name: city,
            nameEn: city, // Fallback
            country: country,
            countryEn: country, // Fallback
            lat: latitude,
            lon: longitude
          });
          setIsEditing(false);
        }
      } catch (error) {
        console.error("Error detecting location:", error);
      } finally {
        setIsDetecting(false);
      }
    }, (error) => {
      console.error("Geolocation error:", error);
      setIsDetecting(false);
      alert(t('geo_denied'));
    });
  };

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

  if (!isEditing && currentCity) {
    return (
      <div className="p-6 bg-white rounded-3xl border border-emerald-100 shadow-sm space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-2 rtl:space-x-reverse">
            <div className="w-8 h-8 bg-emerald-50 rounded-full flex items-center justify-center text-emerald-500">
              <CheckCircle2 className="w-5 h-5" />
            </div>
            <div>
              <p className="text-sm font-bold text-gray-800">{currentCityAr || currentCity}</p>
              <p className="text-[10px] text-gray-400">{isRTL ? 'تم تحديد المدينة' : 'City selected'}</p>
            </div>
          </div>
          <button 
            onClick={() => setIsEditing(true)}
            className="text-xs font-bold text-rose-400 hover:underline"
          >
            {isRTL ? 'تغيير المدينة' : 'Change City'}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="relative space-y-4">
      <div className="flex gap-2">
        <div className="relative flex-1">
          <Search className={cn("absolute top-1/2 -translate-y-1/2 w-5 h-5 text-gray-300", isRTL ? "right-4" : "left-4")} />
          <input 
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onFocus={() => setIsFocused(true)}
            placeholder={isRTL ? "ابحثي عن مدينتك..." : "Search for your city..."}
            className={cn(
              "w-full py-4 bg-white border-2 border-black/5 rounded-2xl text-sm focus:border-rose-300 outline-none transition-all",
              isRTL ? "pr-12 pl-4 text-right" : "pl-12 pr-4 text-left"
            )}
            dir={isRTL ? "rtl" : "ltr"}
          />
          {isLoading && (
            <div className={cn("absolute top-1/2 -translate-y-1/2", isRTL ? "left-12" : "right-12")}>
              <div className="w-4 h-4 border-2 border-rose-300 border-t-transparent rounded-full animate-spin" />
            </div>
          )}
          {query && (
            <button 
              onClick={() => setQuery('')}
              className={cn("absolute top-1/2 -translate-y-1/2 p-1 hover:bg-gray-100 rounded-full", isRTL ? "left-4" : "right-4")}
            >
              <X className="w-4 h-4 text-gray-400" />
            </button>
          )}
        </div>
        
        <button
          onClick={detectLocation}
          disabled={isDetecting}
          className="px-4 bg-rose-50 text-rose-400 rounded-2xl border border-rose-100 hover:bg-rose-100 transition-colors flex items-center justify-center disabled:opacity-50"
          title={isRTL ? "حددي موقعي تلقائياً" : "Detect my location"}
        >
          {isDetecting ? (
            <div className="w-5 h-5 border-2 border-rose-400 border-t-transparent rounded-full animate-spin" />
          ) : (
            <MapPin className="w-5 h-5" />
          )}
        </button>
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
                onClick={() => {
                  onSelect(city);
                  setIsEditing(false);
                  setIsFocused(false);
                  setQuery('');
                }}
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
    </div>
  );
};

export const Profile = ({ onOpenGhusl, onOpenJourneys, onOpenAdah }: ProfileProps) => {
  const { 
    user: contextUser, 
    refresh, 
    fiqhState, 
    currentDay, 
    cycleStats,
    prediction, 
    ovulation 
  } = useCycleData();
  const [user, setUser] = useState<any>(null);
  const [isPremium, setIsPremium] = useState(true); // Freemium
  const [showMadhhabConfirm, setShowMadhhabConfirm] = useState<Madhhab | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [loading, setLoading] = useState(true);
  const [showPaywall, setShowPaywall] = useState(false);
  const [showClinicShare, setShowClinicShare] = useState(false);
  const [clinicCode, setClinicCode] = useState('');
  const [shareType, setShareType] = useState<'health' | 'full'>('health');
  const [ledger, setLedger] = useState<any[]>([]);
  const [entries, setEntries] = useState<any[]>([]);
  const [isGeneratingFiqhPDF, setIsGeneratingFiqhPDF] = useState(false);
  const [isGeneratingDoctorPDF, setIsGeneratingDoctorPDF] = useState(false);
  const [isGeneratingHusbandPDF, setIsGeneratingHusbandPDF] = useState(false);
  const { t, language, setLanguage } = useTranslation();

  useEffect(() => {
    if (contextUser) {
      setUser(contextUser);
      setLoading(false);
    } else {
      async function loadData() {
        const { data: userData } = await api.getUser();
        if (userData) {
          setUser(userData);
          setIsPremium(true); // Freemium
        }
        
        const { data: ledgerData } = await api.getAdahLedger();
        if (ledgerData) setLedger(ledgerData);
        
        const { data: entriesData } = await api.getCycleEntries();
        if (entriesData) setEntries(entriesData);

        setLoading(false);
      }
      loadData();
    }
  }, [contextUser]);

  const handleUpdateUser = async (updates: any) => {
    const { data } = await api.updateUser(updates);
    if (data) {
      setUser(data);
      await refresh();
    }
  };

  const handleInvite = async () => {
    if (navigator.share) {
      try {
        await navigator.share({
          title: 'Niswah App',
          text: 'Check out Niswah - The Fiqh-first cycle tracker for Muslim sisters.',
          url: window.location.origin
        });
      } catch (e) {
        console.error("Share failed", e);
      }
    } else {
      navigator.clipboard.writeText(window.location.origin);
      alert("Link copied to clipboard!");
    }
  };

  const handleRate = () => {
    window.open('https://niswah.app/rate', '_blank');
  };

  const handleDeleteAccount = async () => {
    setIsDeleting(true);
    try {
      const { data, error } = await api.deleteAccount();
      if (data) {
        window.location.reload(); // Shows onboarding
      } else {
        alert(error || "Failed to delete account");
      }
    } catch (e) {
      console.error("Delete failed", e);
    } finally {
      setIsDeleting(false);
      setShowDeleteConfirm(false);
    }
  };

  const handleDownloadFiqhReport = async () => {
    if (!user) return;
    setIsGeneratingFiqhPDF(true);
    try {
      const { pdf } = await import('@react-pdf/renderer');
      const { FiqhReport } = await import('./Reports');
      const safeUser = {
        ...user,
        id: user?.id ?? user?.uid ?? 'anonymous',
        display_name: user?.display_name ?? 'أخت',
        madhhab: user?.madhhab ?? 'HANBALI',
        anonymous_mode: user?.anonymous_mode ?? false,
      };
      const safeLedger = ledger ?? [];
      const blob = await pdf(
        <FiqhReport user={safeUser} ledger={safeLedger} fiqhState={fiqhState} t={t} />
      ).toBlob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `niswah-fiqh-${format(new Date(), 'yyyy-MM-dd')}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err: any) {
      console.error('Fiqh PDF error:', err?.message, err?.stack);
      alert(`خطأ في تقرير الفقه: ${err?.message}`);
    } finally {
      setIsGeneratingFiqhPDF(false);
    }
  };

  const handleDownloadDoctorReport = async () => {
    if (!user) return;
    setIsGeneratingDoctorPDF(true);
    try {
      const { pdf } = await import('@react-pdf/renderer');
      const { DoctorReport } = await import('./Reports');
      
      const safeUser = {
        ...user,
        id: user?.id ?? user?.uid ?? 'anonymous',
        display_name: user?.display_name ?? 'أخت',
        madhhab: user?.madhhab ?? 'HANBALI',
        anonymous_mode: user?.anonymous_mode ?? false,
      };
      const safeLedger = ledger ?? [];
      
      // Calculate stats from ledger
      const stats = {
        avgCycleLength: cycleStats.avgCycleLength?.toFixed(1) ?? null,
        avgHaidDuration: safeLedger.length > 0 ? (safeLedger.reduce((acc, curr) => acc + (curr.haid_duration_hours || 0), 0) / safeLedger.length / 24).toFixed(1) : '6',
        regularityScore: safeLedger.length > 1 ? 'High' : 'Medium',
        shortestCycle: safeLedger.length > 0 ? Math.min(...safeLedger.map(l => (l.tuhr_duration_days || 0) + ((l.haid_duration_hours || 0) / 24))).toFixed(1) : '...',
        longestCycle: safeLedger.length > 0 ? Math.max(...safeLedger.map(l => (l.tuhr_duration_days || 0) + ((l.haid_duration_hours || 0) / 24))).toFixed(1) : '...'
      };

      const blob = await pdf(<DoctorReport user={safeUser} stats={stats} ledger={safeLedger} t={t} />).toBlob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `niswah-doctor-report-${format(new Date(), 'yyyy-MM-dd')}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err: any) {
      console.error('Doctor PDF error:', err?.message, err?.stack);
      alert(`خطأ في تقرير الطبيب: ${err?.message}`);
    } finally {
      setIsGeneratingDoctorPDF(false);
    }
  };

  const handleDownloadHusbandReport = async () => {
    if (!user) {
      alert('لا توجد بيانات مستخدم');
      return;
    }
    setIsGeneratingHusbandPDF(true);
    try {
      const { pdf } = await import('@react-pdf/renderer');
      const { HusbandReport } = await import('./Reports');
      
      const safeUser = {
        id: user?.id ?? user?.uid ?? 'anonymous',
        display_name: user?.display_name ?? 'أخت',
        madhhab: user?.madhhab ?? 'HANBALI',
        anonymous_mode: user?.anonymous_mode ?? false,
        trying_to_conceive: user?.trying_to_conceive ?? false,
        language: user?.language ?? 'ar'
      };

      // ADD THIS — logs exact values before crash
      console.log('DEBUG safeUser:', JSON.stringify(safeUser));
      console.log('DEBUG currentDay:', currentDay);
      console.log('DEBUG fiqhState:', fiqhState);
      console.log('DEBUG prediction:', JSON.stringify(prediction));
      console.log('DEBUG ovulation:', JSON.stringify(ovulation));

      const blob = await pdf(
        <HusbandReport
          user={safeUser}
          currentDay={currentDay}
          fiqhState={fiqhState ?? 'TAHARA'}
          nextPeriodDate={prediction?.predictedStartDate ? new Date(prediction.predictedStartDate) : null}
          fertilityStart={ovulation?.fertileWindowStart ? new Date(ovulation.fertileWindowStart) : null}
          fertilityEnd={ovulation?.fertileWindowEnd ? new Date(ovulation.fertileWindowEnd) : null}
          t={t}
        />
      ).toBlob();

      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `niswah-husband-${format(new Date(), 'yyyy-MM-dd')}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err: any) {
      console.error('FULL ERROR:', err);
      console.error('STACK:', err?.stack);
      alert(`خطأ: ${err?.message}`);
    } finally {
      setIsGeneratingHusbandPDF(false);
    }
  };

  if (loading) return null;

  return (
    <div className="min-h-screen bg-[#FDFCFB] pb-32">
      {/* Header */}
      <header className="px-6 pt-12 pb-6">
        <h1 className="text-3xl font-serif font-bold text-rose-800">{t('profile')}</h1>
      </header>

      <div className="px-6 space-y-8">
        {/* User Card */}
        <section className="p-6 bg-white rounded-[40px] shadow-xl shadow-black/5 border border-black/5 flex items-center space-x-6">
          <motion.div 
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            className="w-20 h-20 rounded-full bg-rose-50 flex items-center justify-center text-2xl font-serif font-bold text-rose-400 border-4 border-rose-50"
          >
            {user?.display_name?.charAt(0) || 'U'}
          </motion.div>
          <div className="flex-1 space-y-1">
            <div className="flex items-center space-x-2">
              <h2 className="text-xl font-bold text-rose-800">{user?.display_name}</h2>
              <motion.div 
                animate={{ opacity: [0.5, 1, 0.5] }}
                transition={{ repeat: Infinity, duration: 2 }}
                className="px-2 py-0.5 bg-amber-50 rounded-full text-[8px] font-bold text-amber-500 uppercase tracking-widest border border-amber-100"
              >
                Plus
              </motion.div>
            </div>
            <p className="text-xs text-gray-400">{user?.email_hash ? t('verified_account') : t('guest_user')}</p>
          </div>
        </section>

        {/* Prayer Times Settings */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">أوقات الصلاة</h3>
          
          <CitySearch 
            currentCity={user?.prayerCity} 
            currentCountry={user?.prayerCountry}
            currentCityAr={user?.prayerCityAr}
            onSelect={async (city) => {
            await handleUpdateUser({
              prayerCity: city.nameEn,
              prayerCountry: city.countryEn,
              prayerCityAr: city.name,
              prayerCountryAr: city.country,
              prayerLat: city.lat,
              prayerLon: city.lon
            });
          }}
        />
      </section>

        {/* Madhhab Selector */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('fiqh_school')}</h3>
          <div className="grid grid-cols-2 gap-3">
            {(['HANAFI', 'SHAFII', 'MALIKI', 'HANBALI'] as Madhhab[]).map((m) => (
              <motion.button
                key={m}
                whileTap={{ scale: 0.95 }}
                onClick={() => setShowMadhhabConfirm(m)}
                className={cn(
                  "p-4 rounded-3xl border transition-all text-left space-y-1",
                  user?.madhhab === m 
                    ? "bg-rose-50 border-rose-200 shadow-sm" 
                    : "bg-white border-black/5"
                )}
              >
                <div className="flex items-center justify-between">
                  <span className={cn("text-sm font-black", user?.madhhab === m ? "text-black" : "text-gray-400")}>
                    {t(m.toLowerCase() as any)}
                  </span>
                  {user?.madhhab === m && <Check className="w-4 h-4 text-rose-400" />}
                </div>
                <p className="text-[8px] text-gray-400 font-medium rtl:text-right">
                  {m === 'HANAFI' ? t('hanafi_desc') : m === 'SHAFII' ? t('shafii_desc') : m === 'MALIKI' ? t('maliki_desc' as any) : t('hanbali_desc' as any)}
                </p>
              </motion.button>
            ))}
          </div>
        </section>

        {/* Essential Tools */}
        <section className="space-y-3">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('essential_tools')}</h3>
          <div className="bg-white rounded-[32px] border border-black/5 overflow-hidden">
            <LinkRow icon={Calendar} label={t('adah_ledger')} onClick={onOpenAdah} />
            <LinkRow icon={BookOpen} label={t('ghusl_guide')} onClick={onOpenGhusl} />
            <LinkRow icon={Sparkles} label={t('journeys')} onClick={onOpenJourneys} />
            <LinkRow icon={Share2} label={t('invite_friends' as any)} onClick={() => {}} />
            <LinkRow icon={Heart} label={t('rate_app' as any)} onClick={() => {}} />
          </div>
        </section>

        {/* Health Profile */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('health_profile')}</h3>
          <div className="bg-white rounded-[32px] border border-black/5 overflow-hidden">
            <ToggleRow 
              label={t('currently_pregnant')} 
              active={user?.pregnant} 
              onChange={(val) => handleUpdateUser({ pregnant: val })} 
            />
            <ToggleRow 
              label={t('postpartum_mode')} 
              active={user?.conditions?.includes('postpartum')} 
              onChange={(val) => {
                const conditions = user?.conditions || [];
                handleUpdateUser({ 
                  conditions: val ? [...conditions, 'postpartum'] : conditions.filter((c: string) => c !== 'postpartum')
                });
              }} 
            />
            <ToggleRow 
              label={t('ttc_mode')} 
              active={user?.conditions?.includes('ttc')} 
              onChange={(val) => {
                const conditions = user?.conditions || [];
                handleUpdateUser({ 
                  conditions: val ? [...conditions, 'ttc'] : conditions.filter((c: string) => c !== 'ttc')
                });
              }} 
            />
            <ToggleRow 
              label={t('health_profile')} 
              active={user?.reflect_health} 
              onChange={(val) => handleUpdateUser({ reflect_health: val })} 
            />
            <p className="px-5 py-3 text-[9px] text-gray-400 italic leading-relaxed rtl:text-right">
              {t('health_profile_toggle_desc')}
            </p>
          </div>
        </section>

        {/* Privacy & Security */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('privacy_settings')}</h3>
          <div className="bg-white rounded-[32px] border border-black/5 overflow-hidden">
            <ToggleRow 
              icon={EyeOff}
              label={t('anonymous_mode')} 
              active={user?.anonymous_mode} 
              onChange={(val) => handleUpdateUser({ anonymous_mode: val })} 
            />
            <LinkRow icon={Lock} label={t('internal_tracking')} onClick={() => {}} />
            <ToggleRow 
              icon={Fingerprint}
              label={t('biometric_lock')} 
              active={user?.biometric_lock ?? false} 
              onChange={(val) => handleUpdateUser({ biometric_lock: val })} 
            />
            <LinkRow icon={Stethoscope} label={t('share_provider')} onClick={() => setShowClinicShare(true)} />
            
            <div className="w-full p-5 flex items-center justify-between hover:bg-gray-50 transition-colors border-b border-black/5">
              <div className="flex items-center space-x-3">
                <Download className="w-5 h-5 text-rose-400" />
                <span className="text-sm font-bold text-rose-800">{t('export_fiqh')}</span>
              </div>
              <button 
                onClick={handleDownloadFiqhReport}
                disabled={isGeneratingFiqhPDF}
                className="text-[10px] font-bold text-rose-400 uppercase tracking-widest disabled:opacity-50"
              >
                {isGeneratingFiqhPDF ? t('preparing') : t('download')}
              </button>
            </div>

            <div className="w-full p-5 flex items-center justify-between hover:bg-gray-50 transition-colors border-b border-black/5">
              <div className="flex items-center space-x-3">
                <Download className="w-5 h-5 text-rose-400" />
                <span className="text-sm font-bold text-rose-800">{t('export_doctor')}</span>
              </div>
              <button 
                onClick={handleDownloadDoctorReport}
                disabled={isGeneratingDoctorPDF}
                className="text-[10px] font-bold text-rose-400 uppercase tracking-widest disabled:opacity-50"
              >
                {isGeneratingDoctorPDF ? t('preparing') : t('download')}
              </button>
            </div>

            <div className="w-full p-5 flex items-center justify-between hover:bg-gray-50 transition-colors border-b border-black/5">
              <div className="flex items-center space-x-3">
                <Download className="w-5 h-5 text-rose-400" />
                <span className="text-sm font-bold text-rose-800">{t('husband_report_title')}</span>
              </div>
              <button 
                onClick={handleDownloadHusbandReport}
                disabled={isGeneratingHusbandPDF}
                className="text-[10px] font-bold text-rose-400 uppercase tracking-widest disabled:opacity-50"
              >
                {isGeneratingHusbandPDF ? t('preparing') : t('download')}
              </button>
            </div>

            <LinkRow icon={Share2} label={t('invite_friends')} onClick={handleInvite} />
            <LinkRow icon={Star} label={t('rate_app')} onClick={handleRate} />
            <LinkRow icon={Trash2} label={t('delete_account')} color="text-rose-500" onClick={() => setShowDeleteConfirm(true)} />
          </div>
        </section>

        {/* Delete Confirmation Overlay */}
        <AnimatePresence>
          {showDeleteConfirm && (
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm z-[100] flex items-end sm:items-center justify-center p-4"
              onClick={() => !isDeleting && setShowDeleteConfirm(false)}
            >
              <motion.div 
                initial={{ y: 100 }}
                animate={{ y: 0 }}
                exit={{ y: 100 }}
                className="bg-white w-full max-w-md rounded-[32px] p-8 space-y-6"
                onClick={e => e.stopPropagation()}
              >
                <div className="space-y-2 text-center">
                  <h3 className="text-xl font-serif font-bold text-rose-900">{t('delete_account_confirm_title')}</h3>
                  <p className="text-sm text-rose-900/60 leading-relaxed">
                    {t('delete_account_confirm_desc')}
                  </p>
                </div>
                
                <div className="space-y-3 pt-4">
                  <button 
                    onClick={handleDeleteAccount}
                    disabled={isDeleting}
                    className="w-full py-4 bg-rose-600 text-white rounded-2xl font-bold text-sm shadow-lg shadow-rose-200 disabled:opacity-50"
                  >
                    {isDeleting ? t('deleting') : t('confirm_delete')}
                  </button>
                  <button 
                    onClick={() => setShowDeleteConfirm(false)}
                    disabled={isDeleting}
                    className="w-full py-4 bg-gray-50 text-gray-400 rounded-2xl font-bold text-sm"
                  >
                    {t('cancel')}
                  </button>
                </div>
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Notifications */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('notifications')}</h3>
          <div className="bg-white rounded-[32px] border border-black/5 overflow-hidden">
            <ToggleRow 
              label={t('prayer_alerts')} 
              active={user?.notification_prefs?.prayer_alerts ?? true} 
              onChange={(val) => {
                const newPrefs = { ...user?.notification_prefs, prayer_alerts: val };
                handleUpdateUser({ notification_prefs: newPrefs });
                if (user?.uid) NotificationService.savePreferences(user.uid, newPrefs);
              }} 
            />
            <ToggleRow 
              label={t('haid_prediction_alerts')} 
              active={user?.notification_prefs?.haid_prediction_alerts ?? true} 
              onChange={(val) => {
                const newPrefs = { ...user?.notification_prefs, haid_prediction_alerts: val };
                handleUpdateUser({ notification_prefs: newPrefs });
                if (user?.uid) NotificationService.savePreferences(user.uid, newPrefs);
              }} 
            />
            <ToggleRow 
              label={t('ghusl_reminders')} 
              active={user?.notification_prefs?.ghusl_reminders ?? true} 
              onChange={(val) => {
                const newPrefs = { ...user?.notification_prefs, ghusl_reminders: val };
                handleUpdateUser({ notification_prefs: newPrefs });
                if (user?.uid) NotificationService.savePreferences(user.uid, newPrefs);
              }} 
            />
            <ToggleRow 
              label={t('daily_insight_alerts')} 
              active={user?.notification_prefs?.daily_insight_alerts ?? true} 
              onChange={(val) => {
                const newPrefs = { ...user?.notification_prefs, daily_insight_alerts: val };
                handleUpdateUser({ notification_prefs: newPrefs });
                if (user?.uid) NotificationService.savePreferences(user.uid, newPrefs);
              }} 
            />
          </div>
        </section>

        {/* Language */}
        <section className="space-y-4">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest px-2">{t('app_settings')}</h3>
          <div className="bg-white rounded-[32px] border border-black/5 overflow-hidden">
            <div className="p-5 flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <Globe className="w-5 h-5 text-rose-400" />
                <span className="text-sm font-bold text-rose-800">{t('language')}</span>
              </div>
              <div className="flex items-center space-x-2">
                <button 
                  onClick={() => setLanguage('en')}
                  className={cn("text-xs font-bold uppercase tracking-widest px-2 py-1 rounded-lg", language === 'en' ? "bg-rose-50 text-rose-400" : "text-gray-400")}
                >
                  EN
                </button>
                <button 
                  onClick={() => setLanguage('ar')}
                  className={cn("text-xs font-bold uppercase tracking-widest px-2 py-1 rounded-lg", language === 'ar' ? "bg-rose-50 text-rose-400" : "text-gray-400")}
                >
                  AR
                </button>
              </div>
            </div>
          </div>
        </section>

        <div className="pt-8 pb-12 text-center">
          <p className="text-[10px] font-bold text-gray-300 uppercase tracking-widest">Niswah v1.0.0</p>
        </div>
      </div>

      {/* Madhhab Confirmation Sheet */}
      <AnimatePresence>
        {showMadhhabConfirm && (
          <>
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowMadhhabConfirm(null)}
              className="fixed inset-0 bg-black/40 z-[200] backdrop-blur-sm"
            />
            <motion.div 
              initial={{ y: '100%' }}
              animate={{ y: 0 }}
              exit={{ y: '100%' }}
              className="fixed bottom-0 left-0 right-0 bg-white rounded-t-[40px] z-[201] p-8 space-y-6"
            >
              <div className="w-12 h-1.5 bg-gray-100 rounded-full mx-auto" />
              <div className="space-y-2 text-center">
                <div className="w-16 h-16 bg-amber-50 rounded-full flex items-center justify-center mx-auto mb-4">
                  <AlertCircle className="w-8 h-8 text-amber-500" />
                </div>
                <h3 className="text-xl font-serif font-bold text-rose-800">{t('fiqh_school')}?</h3>
                <p className="text-sm text-gray-500 leading-relaxed">
                  {t('madhhab_confirm', { madhhab: showMadhhabConfirm })}
                </p>
              </div>
              <div className="space-y-3">
                <button 
                  onClick={async () => {
                    await handleUpdateUser({ madhhab: showMadhhabConfirm });
                    setShowMadhhabConfirm(null);
                  }}
                  className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold shadow-lg shadow-rose-100"
                >
                  {t('confirm')}
                </button>
                <button 
                  onClick={() => setShowMadhhabConfirm(null)}
                  className="w-full py-4 bg-gray-50 text-rose-800 rounded-2xl font-bold"
                >
                  {t('cancel')}
                </button>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>

      {/* Clinic Sharing Sheet */}
      <AnimatePresence>
        {showClinicShare && (
          <>
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowClinicShare(false)}
              className="fixed inset-0 bg-black/40 z-[200] backdrop-blur-sm"
            />
            <motion.div 
              initial={{ y: '100%' }}
              animate={{ y: 0 }}
              exit={{ y: '100%' }}
              className="fixed bottom-0 left-0 right-0 bg-white rounded-t-[40px] z-[201] p-8 space-y-6"
            >
              <div className="flex justify-between items-center">
                <h3 className="text-2xl font-serif font-bold text-rose-800">{t('share_provider')}</h3>
                <button onClick={() => setShowClinicShare(false)} className="p-2 bg-gray-100 rounded-full">
                  <X className="w-5 h-5 text-gray-400" />
                </button>
              </div>
              
              <div className="space-y-4">
                <div className="space-y-2">
                  <label className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('clinic_code')}</label>
                  <input 
                    type="text" 
                    value={clinicCode}
                    onChange={(e) => setClinicCode(e.target.value)}
                    placeholder={t('enter_6_digit')}
                    className="w-full p-4 bg-gray-50 rounded-2xl border border-black/5 text-sm focus:border-rose-300 outline-none"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('share_type')}</label>
                  <div className="grid grid-cols-2 gap-3">
                    <button 
                      onClick={() => setShareType('health')}
                      className={cn(
                        "p-4 rounded-2xl border-2 text-[10px] font-bold transition-all",
                        shareType === 'health' ? "border-rose-300 bg-rose-50 text-rose-800" : "border-black/5 text-gray-400"
                      )}
                    >
                      {t('health_data_only')}
                    </button>
                    <button 
                      onClick={() => setShareType('full')}
                      className={cn(
                        "p-4 rounded-2xl border-2 text-[10px] font-bold transition-all",
                        shareType === 'full' ? "border-rose-300 bg-rose-50 text-rose-800" : "border-black/5 text-gray-400"
                      )}
                    >
                      {t('health_fiqh')}
                    </button>
                  </div>
                </div>

                <button 
                  onClick={() => {
                    setShowClinicShare(false);
                  }}
                  disabled={!clinicCode}
                  className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold disabled:opacity-50"
                >
                  {t('grant_access')}
                </button>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>

      <Paywall 
        isOpen={showPaywall} 
        onClose={() => setShowPaywall(false)} 
        onPurchase={(plan) => {
          setShowPaywall(false);
          handleUpdateUser({ premium_status: true });
          setIsPremium(true);
        }}
      />
    </div>
  );
};

import { HapticService } from '../services/HapticService.ts';

const LinkRow = ({ icon: Icon, label, onClick, color = "text-rose-800" }: { icon: any, label: string, onClick: () => void, color?: string }) => (
  <button 
    onClick={() => {
      HapticService.light();
      onClick();
    }}
    className="w-full p-5 flex items-center justify-between hover:bg-gray-50 transition-colors border-b border-black/5 last:border-0"
  >
    <div className="flex items-center space-x-3">
      <Icon className={cn("w-5 h-5", color.includes('rose') ? 'text-rose-400' : 'text-rose-400')} />
      <span className={cn("text-sm font-bold", color)}>{label}</span>
    </div>
    <ChevronRight className="w-4 h-4 text-gray-300" />
  </button>
);

const ToggleRow = ({ icon: Icon, label, active, onChange }: { icon?: any, label: string, active: boolean, onChange: (val: boolean) => void }) => (
  <div className="p-5 flex items-center justify-between border-b border-black/5 last:border-0">
    <div className="flex items-center space-x-3">
      {Icon && <Icon className="w-5 h-5 text-rose-400" />}
      <span className="text-sm font-bold text-rose-800">{label}</span>
    </div>
    <button 
      onClick={() => {
        HapticService.medium();
        onChange(!active);
      }}
      className={cn(
        "w-12 h-6 rounded-full relative transition-colors duration-300",
        active ? "bg-rose-400" : "bg-gray-200"
      )}
    >
      <motion.div 
        animate={{ x: active ? 24 : 4 }}
        className="absolute top-1 w-4 h-4 bg-white rounded-full shadow-sm"
      />
    </button>
  </div>
);
