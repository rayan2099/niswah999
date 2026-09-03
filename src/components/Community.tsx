/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  MessageSquare, 
  Heart, 
  Share2, 
  MoreHorizontal, 
  Plus, 
  Search, 
  Users, 
  TrendingUp,
  Shield,
  User,
  Image as ImageIcon,
  Send
} from 'lucide-react';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface Post {
  id: string;
  author: string;
  avatar: string;
  content: string;
  timestamp: string;
  likes: number;
  comments: number;
  isAnonymous: boolean;
  category: string;
}

const MOCK_POSTS: Post[] = [
  {
    id: '1',
    author: 'مريم أحمد',
    avatar: 'https://picsum.photos/seed/user1/100/100',
    content: 'السلام عليكم يا أخوات، هل من نصيحة لتخفيف آلام الدورة الشهرية بطرق طبيعية؟ جربت شاي الزنجبيل ولكن أحتاج للمزيد من الاقتراحات.',
    timestamp: '2h ago',
    likes: 24,
    comments: 12,
    isAnonymous: false,
    category: 'صحة'
  },
  {
    id: '2',
    author: 'أخت مجهولة',
    avatar: '',
    content: 'أشعر بضيق شديد خلال هذه الأيام من دورتي، هل هذا طبيعي؟ كيف تتعاملون مع التغيرات المزاجية الحادة؟',
    timestamp: '4h ago',
    likes: 45,
    comments: 30,
    isAnonymous: true,
    category: 'صحة نفسية'
  },
  {
    id: '3',
    author: 'فاطمة علي',
    avatar: 'https://picsum.photos/seed/user3/100/100',
    content: 'الحمد لله، أكملت اليوم أول رحلة إرشادية في التطبيق عن فقه الطهارة. أنصح الجميع بها، المعلومات قيمة جداً ومبسطة.',
    timestamp: '6h ago',
    likes: 89,
    comments: 15,
    isAnonymous: false,
    category: 'فقه'
  }
];

import { useCycleData } from '../contexts/CycleContext.tsx';

export const Community = () => {
  const { t, isRTL } = useTranslation();
  const { user } = useCycleData();
  const [posts, setPosts] = useState<Post[]>(MOCK_POSTS);
  const [isCreating, setIsCreating] = useState(false);
  const [newPostContent, setNewPostContent] = useState('');
  const [isAnonymous, setIsAnonymous] = useState(user?.anonymous_mode || false);

  const handleCreatePost = () => {
    if (!newPostContent.trim()) return;
    
    const authorName = isAnonymous ? t('guest_user') : (user?.display_name || 'أنا');
    
    const newPost: Post = {
      id: Date.now().toString(),
      author: authorName,
      avatar: isAnonymous ? '' : (user?.avatar || 'https://picsum.photos/seed/me/100/100'),
      content: newPostContent,
      timestamp: 'Just now',
      likes: 0,
      comments: 0,
      isAnonymous,
      category: 'عام'
    };

    setPosts([newPost, ...posts]);
    setNewPostContent('');
    setIsCreating(false);
    setIsAnonymous(false);
  };

  return (
    <div className="min-h-screen bg-[#FDFCFB] pb-32">
      {/* Header */}
      <header className="px-6 pt-12 pb-6 bg-white border-b border-black/5 sticky top-0 z-20">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-3xl font-serif font-bold text-rose-800">{t('community')}</h1>
          <div className="flex items-center space-x-3">
            <button className="w-10 h-10 bg-rose-50 rounded-full flex items-center justify-center text-rose-400">
              <Search className="w-5 h-5" />
            </button>
            <button className="w-10 h-10 bg-rose-50 rounded-full flex items-center justify-center text-rose-400">
              <Users className="w-5 h-5" />
            </button>
          </div>
        </div>
        <p className="text-xs text-gray-400 leading-relaxed max-w-[280px]">
          {t('community_intro')}
        </p>
      </header>

      <div className="p-6 space-y-8">
        {/* Create Post Trigger */}
        <motion.div 
          whileTap={{ scale: 0.98 }}
          onClick={() => setIsCreating(true)}
          className="p-4 bg-white rounded-[32px] border border-black/5 shadow-sm flex items-center space-x-4 cursor-pointer"
        >
          <div className="w-10 h-10 rounded-full bg-rose-50 flex items-center justify-center text-rose-200">
            <User className="w-5 h-5" />
          </div>
          <span className="text-sm text-gray-400">{t('post_placeholder')}</span>
          <div className="flex-1" />
          <div className="w-10 h-10 bg-rose-600 rounded-full flex items-center justify-center text-white shadow-lg shadow-rose-200">
            <Plus className="w-5 h-5" />
          </div>
        </motion.div>

        {/* Trending Topics */}
        <section className="space-y-4">
          <div className="flex items-center space-x-2">
            <TrendingUp className="w-4 h-4 text-rose-400" />
            <h3 className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('trending_topics')}</h3>
          </div>
          <div className={cn("flex overflow-x-auto no-scrollbar space-x-3", isRTL && "space-x-reverse")}>
            {['#فقه_الطهارة', '#صحة_المرأة', '#رمضان_٢٠٢٤', '#تكيس_المبايض'].map((tag) => (
              <span key={tag} className="px-4 py-2 bg-rose-50 text-rose-800 text-xs font-bold rounded-full border border-rose-100 whitespace-nowrap">
                {tag}
              </span>
            ))}
          </div>
        </section>

        {/* Posts Feed */}
        <div className="space-y-6">
          {posts.map((post) => (
            <PostCard key={post.id} post={post} />
          ))}
        </div>
      </div>

      {/* Create Post Modal */}
      <AnimatePresence>
        {isCreating && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[400] bg-black/40 backdrop-blur-sm flex items-end sm:items-center justify-center p-4"
          >
            <motion.div 
              initial={{ y: 100 }}
              animate={{ y: 0 }}
              exit={{ y: 100 }}
              className="w-full max-w-lg bg-white rounded-[40px] overflow-hidden shadow-2xl"
            >
              <div className="p-6 border-b border-black/5 flex items-center justify-between">
                <h3 className="text-lg font-serif font-bold text-rose-900">{t('create_post')}</h3>
                <button onClick={() => setIsCreating(false)} className="p-2 hover:bg-gray-100 rounded-full transition-colors">
                  <X className="w-5 h-5 text-gray-400" />
                </button>
              </div>
              <div className="p-6 space-y-4">
                <textarea 
                  autoFocus
                  value={newPostContent}
                  onChange={(e) => setNewPostContent(e.target.value)}
                  placeholder={t('post_placeholder')}
                  className="w-full h-40 bg-transparent border-none outline-none text-rose-900 placeholder:text-gray-300 resize-none text-lg leading-relaxed"
                />
                
                <div className="flex items-center justify-between pt-4 border-t border-black/5">
                  <div className="flex items-center space-x-4">
                    <button className="p-2 text-rose-400 hover:bg-rose-50 rounded-xl transition-colors">
                      <ImageIcon className="w-6 h-6" />
                    </button>
                    <div className="flex items-center space-x-2">
                      <button 
                        onClick={() => setIsAnonymous(!isAnonymous)}
                        className={cn(
                          "w-10 h-5 rounded-full relative transition-colors",
                          isAnonymous ? "bg-rose-600" : "bg-gray-200"
                        )}
                      >
                        <div className={cn(
                          "absolute top-1 w-3 h-3 bg-white rounded-full transition-all",
                          isAnonymous ? "right-1" : "left-1"
                        )} />
                      </button>
                      <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{t('post_anonymous')}</span>
                    </div>
                  </div>
                  <button 
                    onClick={handleCreatePost}
                    disabled={!newPostContent.trim()}
                    className={cn(
                      "px-8 py-3 rounded-2xl font-bold text-sm transition-all shadow-lg",
                      newPostContent.trim() ? "bg-rose-600 text-white shadow-rose-200" : "bg-gray-100 text-gray-300 shadow-none"
                    )}
                  >
                    {t('post_button')}
                  </button>
                </div>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

const PostCard = ({ post }: { post: Post }) => {
  const { t, isRTL } = useTranslation();
  const [liked, setLiked] = useState(false);

  return (
    <motion.div 
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      className="bg-white rounded-[40px] p-6 border border-black/5 shadow-sm space-y-4"
    >
      <div className="flex items-center justify-between">
        <div className={cn("flex items-center space-x-3", isRTL && "space-x-reverse")}>
          <div className="w-10 h-10 rounded-2xl overflow-hidden bg-rose-50 flex items-center justify-center">
            {post.isAnonymous ? (
              <Shield className="w-5 h-5 text-rose-200" />
            ) : (
              <img src={post.avatar} alt={post.author} className="w-full h-full object-cover" referrerPolicy="no-referrer" />
            )}
          </div>
          <div>
            <h4 className="text-sm font-bold text-rose-900">{post.isAnonymous ? t('guest_user') : post.author}</h4>
            <p className="text-[10px] text-gray-400 font-medium">{post.timestamp} · {post.category}</p>
          </div>
        </div>
        <button className="p-2 text-gray-300 hover:text-rose-400 transition-colors">
          <MoreHorizontal className="w-5 h-5" />
        </button>
      </div>

      <p className="text-sm text-rose-900 leading-relaxed">
        {post.content}
      </p>

      <div className="pt-4 border-t border-black/5 flex items-center justify-between">
        <div className={cn("flex items-center space-x-6", isRTL && "space-x-reverse")}>
          <button 
            onClick={() => setLiked(!liked)}
            className={cn(
              "flex items-center space-x-2 transition-colors",
              liked ? "text-rose-600" : "text-gray-400"
            )}
          >
            <Heart className={cn("w-5 h-5", liked && "fill-rose-600")} />
            <span className="text-xs font-bold">{post.likes + (liked ? 1 : 0)}</span>
          </button>
          <button className="flex items-center space-x-2 text-gray-400">
            <MessageSquare className="w-5 h-5" />
            <span className="text-xs font-bold">{post.comments}</span>
          </button>
        </div>
        <button className="p-2 text-gray-400 hover:text-rose-600 transition-colors">
          <Share2 className="w-5 h-5" />
        </button>
      </div>
    </motion.div>
  );
};

const X = ({ className }: { className?: string }) => (
  <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M18 6L6 18M6 6l12 12" />
  </svg>
);
