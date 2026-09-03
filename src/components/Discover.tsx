/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence, useScroll, useTransform } from 'framer-motion';
import { 
  Search, 
  Play, 
  Headphones, 
  BookOpen, 
  HelpCircle, 
  FileText, 
  CheckCircle2, 
  Star, 
  Calendar as CalendarIcon,
  Lock,
  MessageSquare,
  ChevronRight,
  Heart,
  ShieldCheck,
  Volume2,
  Pause,
  X,
  Moon,
  Sparkles
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { useTranslation } from '../i18n/LanguageContext.tsx';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// --- TYPES ---

type ContentType = 'Article' | 'Video' | 'Audio' | 'Quiz' | 'Guide';

interface ContentCard {
  id: string;
  category: string;
  categoryKey: string;
  title: string;
  titleKey?: string;
  author: string;
  authorKey?: string;
  type: ContentType;
  thumbnail: string;
  verified?: boolean;
}

interface Scholar {
  id: string;
  name: string;
  nameKey?: string;
  credential: string;
  specialization: string;
  specializationKey?: string;
  nextSlot: string;
  rating: number;
  photo: string;
}

// --- MOCK DATA ---

const CATEGORIES = [
  'all', 'fiqh', 'nutrition', 'spiritual', 'pregnancy', 
  'medical', 'mental_health', 'partners', 'pcos', 'fertility'
];

const CONTENT_CARDS: ContentCard[] = [
  { id: '1', category: 'Fiqh', categoryKey: 'fiqh', title: 'Understanding Tahara: A Deep Dive', titleKey: 'spiritual_significance', author: 'Ustadha Maryam', authorKey: 'ustadha_maryam', type: 'Article', thumbnail: 'https://picsum.photos/seed/fiqh1/400/300', verified: true },
  { id: '2', category: 'Nutrition', categoryKey: 'nutrition', title: 'Cycle Syncing Your Diet', titleKey: 'nutrition_luteal', author: 'Dr. Sarah Ahmed', authorKey: 'dr_sarah', type: 'Video', thumbnail: 'https://picsum.photos/seed/nutri1/400/300', verified: true },
  { id: '3', category: 'Medical', categoryKey: 'medical', title: 'PCOS Management in Islam', author: 'Dr. Fatima Khan', authorKey: 'dr_fatima', type: 'Guide', thumbnail: 'https://picsum.photos/seed/med1/400/300', verified: true },
  { id: '4', category: 'Mental Health', categoryKey: 'mental_health', title: 'Mindfulness and Dhikr', author: 'Zainab Qureshi', authorKey: 'zainab_qureshi', type: 'Audio', thumbnail: 'https://picsum.photos/seed/mental1/400/300', verified: true },
];

const SCHOLARS: Scholar[] = [
  { id: 's1', name: 'Ustadha Amina', nameKey: 'ustadha_amina', credential: 'ma_islamic_law', specialization: 'Hanafi Fiqh', specializationKey: 'hanafi', nextSlot: 'next_slot_tomorrow', rating: 4.9, photo: 'https://picsum.photos/seed/scholar1/200/200' },
  { id: 's2', name: 'Dr. Layla', nameKey: 'dr_layla', credential: 'obgyn_alimah', specialization: 'Medical Fiqh', specializationKey: 'medical', nextSlot: 'next_slot_wed', rating: 5.0, photo: 'https://picsum.photos/seed/scholar2/200/200' },
];

// --- COMPONENTS ---

const CategoryFilter = ({ active, onChange }: { active: string, onChange: (c: string) => void }) => {
  const { t, isRTL } = useTranslation();
  return (
    <div className={cn("flex overflow-x-auto no-scrollbar py-4 px-6 space-x-2", isRTL && "space-x-reverse")}>
      {CATEGORIES.map((cat) => (
        <button
          key={cat}
          onClick={() => onChange(cat)}
          className="relative px-5 py-2 rounded-full text-sm font-medium transition-colors duration-300 whitespace-nowrap"
        >
          {active === cat && (
            <motion.div
              layoutId="active-pill"
              className="absolute inset-0 bg-rose-400 rounded-full"
              transition={{ type: 'spring', bounce: 0.2, duration: 0.6 }}
            />
          )}
          <span className={cn(
            "relative z-10",
            active === cat ? "text-white" : "text-rose-800/60 border border-rose-900/10"
          )}>
            {t(cat as any)}
          </span>
        </button>
      ))}
    </div>
  );
};

const FeaturedCard = () => {
  const { t } = useTranslation();
  const ref = useRef(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"]
  });
  
  const y = useTransform(scrollYProgress, [0, 1], ["0%", "20%"]);

  return (
    <motion.div 
      ref={ref}
      className="mx-6 h-[400px] rounded-[40px] overflow-hidden relative group cursor-pointer"
      whileTap={{ scale: 0.98 }}
    >
      <motion.div 
        style={{ y }}
        className="absolute inset-0 bg-gradient-to-br from-rose-200 via-pink-300 to-purple-400 animate-gradient-xy"
      />
      <div className="absolute inset-0 bg-black/20" />
      <div className="absolute bottom-0 left-0 right-0 p-8 text-white">
        <span className="px-3 py-1 bg-white/20 backdrop-blur-md rounded-full text-[10px] font-bold uppercase tracking-widest mb-4 inline-block">{t('featured_story')}</span>
        <h2 className="text-3xl font-serif font-bold mb-2">{t('spiritual_significance')}</h2>
        <div className="flex items-center space-x-3 text-sm opacity-80">
          <span>{t('ustadha_maryam')}</span>
          <span className="w-1 h-1 bg-white rounded-full" />
          <span>8 {t('min_read')}</span>
        </div>
      </div>
    </motion.div>
  );
};

const ContentGridCard = ({ item, index }: { item: ContentCard, index: number }) => {
  const { t, isRTL } = useTranslation();
  const Icon = {
    Article: FileText,
    Video: Play,
    Audio: Headphones,
    Quiz: HelpCircle,
    Guide: BookOpen
  }[item.type];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ delay: index * 0.04 }}
      whileTap={{ scale: 0.96 }}
      className="bg-white rounded-[32px] overflow-hidden shadow-sm border border-black/5 flex flex-col group cursor-pointer"
    >
      <div className="aspect-[4/3] relative overflow-hidden">
        <img src={item.thumbnail} alt={item.title} className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-700" referrerPolicy="no-referrer" />
        <div className={cn(
          "absolute top-3 px-2 py-1 bg-white/90 backdrop-blur-sm rounded-lg text-[8px] font-bold uppercase tracking-wider text-rose-800",
          isRTL ? "right-3" : "left-3"
        )}>
          {t(item.categoryKey as any)}
        </div>
        <div className={cn(
          "absolute bottom-3 w-8 h-8 bg-white/90 backdrop-blur-sm rounded-full flex items-center justify-center shadow-sm",
          isRTL ? "left-3" : "right-3"
        )}>
          <Icon className="w-4 h-4 text-rose-400" />
        </div>
      </div>
      <div className="p-4 space-y-2">
        <h3 className="text-sm font-bold text-rose-800 leading-tight line-clamp-2">{item.titleKey ? t(item.titleKey as any) : item.title}</h3>
        <div className={cn("flex items-center space-x-1", isRTL && "space-x-reverse")}>
          <span className="text-[10px] text-gray-400 font-medium">{item.authorKey ? t(item.authorKey as any) : item.author}</span>
          {item.verified && <CheckCircle2 className="w-3 h-3 text-rose-400" />}
        </div>
      </div>
    </motion.div>
  );
};

const ScholarCard = ({ scholar }: { scholar: Scholar }) => {
  const { t, isRTL } = useTranslation();
  return (
    <motion.div 
      whileHover={{ y: -5 }}
      whileTap={{ scale: 0.96 }}
      className="flex-shrink-0 w-72 bg-white rounded-[40px] p-6 border border-black/5 shadow-xl shadow-black/5 space-y-6 cursor-pointer group"
    >
      <div className={cn("flex items-center space-x-4", isRTL && "space-x-reverse")}>
        <div className="w-20 h-20 rounded-3xl overflow-hidden bg-rose-50 border-4 border-rose-50 shadow-inner">
          <img src={scholar.photo} alt={scholar.name} className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" referrerPolicy="no-referrer" />
        </div>
        <div className="flex-1">
          <div className="flex items-center justify-between">
            <h4 className="font-serif font-bold text-rose-800 text-lg">{scholar.nameKey ? t(scholar.nameKey as any) : scholar.name}</h4>
            <div className="flex items-center space-x-1">
              <Star className="w-3 h-3 text-amber-400 fill-amber-400" />
              <span className="text-xs font-bold text-rose-800">{scholar.rating}</span>
            </div>
          </div>
          <p className="text-[10px] text-rose-400 font-bold uppercase tracking-widest">{t(scholar.credential as any)}</p>
        </div>
      </div>
      
      <div className="grid grid-cols-2 gap-4 py-4 border-y border-black/5">
        <div className="space-y-1">
          <span className="text-[8px] text-gray-400 font-bold uppercase tracking-widest block">{t('specialization')}</span>
          <span className="text-[10px] font-bold text-rose-800">{scholar.specializationKey ? t(scholar.specializationKey as any) : scholar.specialization}</span>
        </div>
        <div className="space-y-1">
          <span className="text-[8px] text-gray-400 font-bold uppercase tracking-widest block">{t('next_slot')}</span>
          <span className="text-[10px] font-bold text-rose-400">{t(scholar.nextSlot as any)}</span>
        </div>
      </div>

      <button className="w-full py-3 bg-rose-50 text-rose-400 rounded-2xl text-[10px] font-bold uppercase tracking-widest hover:bg-rose-400 hover:text-white transition-colors">
        {t('book_now')}
      </button>
    </motion.div>
  );
};

const PartnerSection = () => {
  const { t, isRTL } = useTranslation();
  const [isShared, setIsShared] = useState(false);
  const [showShareModal, setShowShareModal] = useState(false);

  const handleShare = () => {
    if (navigator.share) {
      navigator.share({
        title: t('husband_share_title'),
        text: t('husband_share_text'),
        url: window.location.origin
      }).catch(console.error);
    } else {
      setShowShareModal(true);
    }
  };

  return (
    <section className="mx-6 p-8 bg-rose-50 rounded-[40px] border border-rose-100 space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h3 className="text-xl font-serif font-bold text-rose-800">{t('for_husband')}</h3>
          <p className="text-xs text-rose-400/60">{t('husband_desc')}</p>
        </div>
        <div className="p-3 bg-white rounded-2xl shadow-sm">
          <Heart className="w-6 h-6 text-rose-400" />
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        {[
          { title: t('intimacy_rulings'), icon: ShieldCheck },
          { title: t('cycle_support'), icon: Heart },
          { title: t('understanding_phases'), icon: BookOpen },
          { title: t('islamic_health'), icon: Moon }
        ].map((item, i) => (
          <motion.button
            key={i}
            whileTap={{ scale: 0.95 }}
            className="p-4 bg-white rounded-2xl border border-rose-100 flex flex-col items-center text-center space-y-2"
          >
            <item.icon className="w-5 h-5 text-rose-400" />
            <span className="text-[10px] font-bold text-rose-800 leading-tight">{item.title}</span>
          </motion.button>
        ))}
      </div>
      
      <div className="space-y-4 pt-4 border-t border-rose-100">
        <div className="flex items-center justify-between">
          <div className="flex flex-col">
            <span className="text-xs font-bold text-rose-800">{t('share_visibility')}</span>
            <span className="text-[8px] text-rose-400 font-medium">{t('husband_visibility_desc')}</span>
          </div>
          <button 
            onClick={() => setIsShared(!isShared)}
            className={cn("w-12 h-6 rounded-full relative transition-all", isShared ? "bg-rose-400" : "bg-rose-200")}
          >
            <motion.div animate={{ x: isShared ? 24 : 4 }} className="absolute top-1 w-4 h-4 bg-white rounded-full shadow-sm" />
          </button>
        </div>

        <div className="flex flex-col space-y-3">
          <motion.button
            whileTap={{ scale: 0.98 }}
            onClick={handleShare}
            className="w-full py-4 bg-rose-400 text-white rounded-2xl text-[10px] font-bold uppercase tracking-widest shadow-lg shadow-rose-200 flex items-center justify-center space-x-2"
          >
            <Sparkles className="w-4 h-4" />
            <span>{t('share_with_husband_btn')}</span>
          </motion.button>

          <motion.button
            whileTap={{ scale: 0.98 }}
            className="w-full py-4 bg-white border-2 border-rose-100 text-rose-400 rounded-2xl text-[10px] font-bold uppercase tracking-widest flex items-center justify-center space-x-2"
          >
            <FileText className="w-4 h-4" />
            <span>{t('export_to_husband')}</span>
          </motion.button>
        </div>
      </div>

      <AnimatePresence>
        {showShareModal && (
          <div className="fixed inset-0 z-[300] flex items-center justify-center p-6">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowShareModal(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.9, opacity: 0 }}
              className="bg-white rounded-[40px] p-8 w-full max-w-sm relative z-10 space-y-6"
            >
              <h3 className="text-xl font-serif font-bold text-rose-800">{t('husband_share_title')}</h3>
              <p className="text-sm text-gray-500 leading-relaxed">{t('husband_share_text')}</p>
              <div className="p-4 bg-rose-50 rounded-2xl border border-rose-100 text-xs font-mono text-rose-800 break-all">
                {window.location.origin}/husband-view
              </div>
              <button 
                onClick={() => setShowShareModal(false)}
                className="w-full py-4 bg-rose-400 text-white rounded-2xl font-bold"
              >
                {t('got_it')}
              </button>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </section>
  );
};

const SecretChatsEntry = () => {
  const { t, isRTL } = useTranslation();
  return (
    <motion.div 
      whileTap={{ scale: 0.98 }}
      className="mx-6 p-8 bg-rose-800 rounded-[40px] text-white relative overflow-hidden cursor-pointer"
    >
      <div className={cn("absolute top-0 p-6 opacity-10", isRTL ? "left-0" : "right-0")}>
        <Lock className="w-32 h-32" />
      </div>
      <div className="relative z-10 space-y-4">
        <div className={cn("flex items-center space-x-2", isRTL && "space-x-reverse")}>
          <ShieldCheck className="w-5 h-5 text-rose-300" />
          <span className="text-[10px] font-bold uppercase tracking-widest text-rose-300">{t('encrypted_private')}</span>
        </div>
        <h3 className="text-2xl font-serif font-bold">{t('secret_chats')}</h3>
        <p className="text-sm text-rose-50/60 leading-relaxed">{t('connect_scholars')}</p>
        <div className={cn("flex items-center space-x-2 text-xs font-bold text-rose-300", isRTL && "space-x-reverse")}>
          <span>{t('enter_vault')}</span>
          <ChevronRight className={cn("w-4 h-4", isRTL && "rotate-180")} />
        </div>
      </div>
    </motion.div>
  );
};

const AudioLibrary = () => {
  const { t, isRTL } = useTranslation();
  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between px-6">
        <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('podcasts')}</h3>
        <span className="text-[10px] font-bold text-rose-400 uppercase tracking-widest">{t('view_all')}</span>
      </div>
      <div className={cn("flex overflow-x-auto no-scrollbar space-x-4 px-6 pb-4", isRTL && "space-x-reverse")}>
        {[1, 2, 3].map((i) => (
          <motion.div 
            key={i}
            whileTap={{ scale: 0.96 }}
            className="flex-shrink-0 w-48 space-y-3 cursor-pointer"
          >
            <div className="aspect-square bg-rose-50 rounded-[32px] relative overflow-hidden">
              <img src={`https://picsum.photos/seed/audio${i}/300/300`} alt="Audio" className="w-full h-full object-cover" referrerPolicy="no-referrer" />
              <div className="absolute inset-0 bg-black/10 flex items-center justify-center">
                <div className="w-12 h-12 bg-white/90 backdrop-blur-sm rounded-full flex items-center justify-center shadow-lg">
                  <Play className={cn("w-5 h-5 text-rose-400 fill-rose-400", isRTL ? "mr-1" : "ml-1")} />
                </div>
              </div>
            </div>
            <div>
              <h4 className="text-sm font-bold text-rose-800 leading-tight">{t('episode')} {i}: {t('finding_calm_haid')}</h4>
              <p className="text-[10px] text-gray-400 font-medium">{t('ustadha_amina')} · 15 {t('min_read')}</p>
            </div>
          </motion.div>
        ))}
      </div>
    </section>
  );
};

// --- MAIN DISCOVER SCREEN ---

export const Discover = ({ onOpenAI }: { onOpenAI: () => void }) => {
  const [activeCategory, setActiveCategory] = useState('all');
  const { t, isRTL } = useTranslation();
  const contentRef = useRef<HTMLDivElement>(null);

  const filteredCards = activeCategory === 'all' 
    ? CONTENT_CARDS 
    : CONTENT_CARDS.filter(card => card.categoryKey === activeCategory);

  const handleCategoryChange = (category: string) => {
    setActiveCategory(category);
    if (category !== 'all') {
      setTimeout(() => {
        contentRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 100);
    }
  };

  return (
    <div className="min-h-screen bg-[#FDFCFB] pb-32 space-y-8">
      {/* Header */}
      <header className="px-6 pt-12 pb-4 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-3xl font-serif font-bold text-rose-800">{t('discover')}</h1>
          <div className="w-10 h-10 bg-white rounded-full flex items-center justify-center shadow-sm border border-black/5">
            <Search className="w-5 h-5 text-rose-800" />
          </div>
        </div>
        <CategoryFilter active={activeCategory} onChange={handleCategoryChange} />
      </header>

      {/* Featured */}
      <FeaturedCard />

      {/* Scholar Consultation */}
      <section className="space-y-4">
        <div className="flex items-center justify-between px-6">
          <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('scholar_consultation')}</h3>
          <span className="text-[10px] font-bold text-rose-400 uppercase tracking-widest">{t('view_all')}</span>
        </div>
        <div className={cn("flex overflow-x-auto no-scrollbar space-x-6 px-6 pb-8", isRTL && "space-x-reverse")}>
          {SCHOLARS.map(s => <ScholarCard key={s.id} scholar={s} />)}
        </div>
      </section>

      {/* Content Grid */}
      <section ref={contentRef} className="px-6 space-y-4 scroll-mt-6">
        <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
          {activeCategory === 'all' ? t('all_content') : t(activeCategory as any)}
        </h3>
        <div className="grid grid-cols-2 gap-4">
          {filteredCards.map((item, i) => (
            <ContentGridCard key={item.id} item={item} index={i} />
          ))}
          {filteredCards.length === 0 && (
            <div className="col-span-2 py-12 text-center space-y-2">
              <p className="text-sm text-gray-400">No content found for this category yet.</p>
            </div>
          )}
        </div>
      </section>

      {/* Niswah AI Quick Access */}
      <section className="px-6">
        <motion.div 
          whileTap={{ scale: 0.98 }}
          onClick={onOpenAI}
          className="p-8 bg-white rounded-[40px] shadow-xl shadow-black/5 border border-black/5 flex items-center justify-between cursor-pointer group"
        >
          <div className={cn("flex items-center space-x-4", isRTL && "space-x-reverse")}>
            <div className="w-12 h-12 bg-rose-50 rounded-2xl flex items-center justify-center text-rose-400">
              <Sparkles className="w-6 h-6" />
            </div>
            <div>
              <h3 className="font-bold text-rose-800">{t('ask_nisa')}</h3>
              <p className="text-[10px] text-gray-400">{t('nisa_companion')}</p>
            </div>
          </div>
          <ChevronRight className={cn("w-5 h-5 text-gray-300 group-hover:text-rose-400 transition-colors", isRTL && "rotate-180")} />
        </motion.div>
      </section>

      {/* Audio Library */}
      <AudioLibrary />

      {/* Partner Section */}
      <PartnerSection />
    </div>
  );
};
