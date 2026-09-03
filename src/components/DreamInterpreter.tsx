/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useTranslation } from '../i18n/LanguageContext.tsx';
import { 
  Send, 
  X, 
  Moon, 
  Sparkles, 
  User, 
  MessageSquare,
  ArrowLeft,
  Info
} from 'lucide-react';
import { GoogleGenAI, GenerateContentResponse } from "@google/genai";
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Madhhab } from '../logic/types.ts';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// --- TYPES ---

interface Message {
  id: string;
  role: 'user' | 'interpreter';
  text: string;
  timestamp: number;
}

interface DreamInterpreterProps {
  isOpen: boolean;
  onClose: () => void;
  userMadhhab: Madhhab;
}

// --- COMPONENTS ---

const MessageBubble = ({ message }: { message: Message }) => {
  const isUser = message.role === 'user';

  return (
    <motion.div
      initial={{ opacity: 0, x: isUser ? 20 : -20, scale: 0.95 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      className={cn(
        "flex w-full mb-6",
        isUser ? "justify-end" : "justify-start"
      )}
    >
      <div className={cn(
        "flex max-w-[85%] items-end space-x-2",
        isUser ? "flex-row-reverse space-x-reverse" : "flex-row"
      )}>
        {!isUser && (
          <div className="w-8 h-8 rounded-full bg-indigo-100 flex items-center justify-center flex-shrink-0 shadow-sm border border-indigo-200">
            <Moon className="w-4 h-4 text-indigo-600" />
          </div>
        )}
        <div className={cn(
          "p-4 rounded-[24px] text-sm leading-relaxed shadow-sm",
          isUser 
            ? "bg-indigo-600 text-white rounded-br-none" 
            : "bg-white text-indigo-900 border border-black/5 rounded-bl-none"
        )}>
          {message.text}
        </div>
      </div>
    </motion.div>
  );
};

const TypingIndicator = () => (
  <div className="flex space-x-1.5 p-4 bg-white rounded-[24px] rounded-bl-none border border-black/5 w-fit mb-6 shadow-sm">
    {[0, 1, 2].map((i) => (
      <motion.div
        key={i}
        animate={{ y: [0, -6, 0] }}
        transition={{ 
          repeat: Infinity, 
          duration: 0.8, 
          delay: i * 0.15,
          ease: "easeInOut"
        }}
        className="w-1.5 h-1.5 bg-indigo-300 rounded-full"
      />
    ))}
  </div>
);

// --- MAIN DREAM INTERPRETER COMPONENT ---

export const DreamInterpreter = ({ isOpen, onClose, userMadhhab }: DreamInterpreterProps) => {
  const { t, isRTL } = useTranslation();
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputText, setInputText] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isTyping]);

  const handleSend = async (text: string = inputText) => {
    if (!text.trim()) return;

    const userMsg: Message = {
      id: Date.now().toString(),
      role: 'user',
      text: text.trim(),
      timestamp: Date.now()
    };

    setMessages(prev => [...prev, userMsg]);
    setInputText('');
    setIsTyping(true);

    try {
      const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
      const systemPrompt = t('dream_system_instruction') + `\n\nUser's Madhhab: ${userMadhhab}`;

      const chatHistory = messages.map(m => ({
        role: m.role === 'user' ? 'user' : 'model',
        parts: [{ text: m.text }]
      }));

      const responseStream = await ai.models.generateContentStream({
        model: "gemini-3.1-pro-preview",
        contents: [
          { role: 'user', parts: [{ text: systemPrompt }] },
          ...chatHistory,
          { role: 'user', parts: [{ text: text.trim() }] }
        ],
      });

      const aiMsgId = (Date.now() + 1).toString();
      let fullText = "";
      
      setMessages(prev => [...prev, {
        id: aiMsgId,
        role: 'interpreter',
        text: "",
        timestamp: Date.now()
      }]);

      for await (const chunk of responseStream) {
        const chunkText = chunk.text;
        if (chunkText) {
          fullText += chunkText;
          setMessages(prev => prev.map(m => m.id === aiMsgId ? { ...m, text: fullText } : m));
        }
      }

    } catch (err) {
      console.error("Dream Interpreter Error:", err);
      const errMsg: Message = {
        id: (Date.now() + 1).toString(),
        role: 'interpreter',
        text: t('nisa_error'),
        timestamp: Date.now()
      };
      setMessages(prev => [...prev, errMsg]);
    } finally {
      setIsTyping(false);
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ y: '100%' }}
          animate={{ y: 0 }}
          exit={{ y: '100%' }}
          transition={{ type: 'spring', damping: 25, stiffness: 200 }}
          className="fixed inset-0 z-[300] bg-[#FDFCFB] flex flex-col"
        >
          {/* Header */}
          <header className="p-6 flex items-center justify-between border-b border-black/5 bg-white/80 backdrop-blur-md sticky top-0 z-10">
            <div className={cn("flex items-center space-x-4", isRTL && "space-x-reverse")}>
              <button onClick={onClose} className="p-2 hover:bg-gray-100 rounded-full transition-colors">
                <ArrowLeft className={cn("w-6 h-6 text-indigo-900", isRTL && "rotate-180")} />
              </button>
              <div className={cn("flex items-center space-x-3", isRTL && "space-x-reverse")}>
                <div className="w-10 h-10 rounded-full bg-indigo-100 flex items-center justify-center shadow-sm border border-indigo-200">
                  <Moon className="w-5 h-5 text-indigo-600" />
                </div>
                <div>
                  <h2 className="text-lg font-serif font-bold text-indigo-900">{t('dream_interpretation')}</h2>
                  <div className={cn("flex items-center space-x-1", isRTL && "space-x-reverse")}>
                    <div className="w-1.5 h-1.5 bg-indigo-500 rounded-full animate-pulse" />
                    <span className="text-[10px] font-bold text-indigo-600 uppercase tracking-widest">{t('online_status')}</span>
                  </div>
                </div>
              </div>
            </div>
            <Sparkles className="w-5 h-5 text-indigo-400" />
          </header>

          {/* Intro Banner */}
          <div className="px-6 py-3 bg-indigo-50 border-b border-indigo-100">
            <div className={cn("flex items-center space-x-2", isRTL && "space-x-reverse")}>
              <Info className="w-3 h-3 text-indigo-600" />
              <span className="text-[10px] font-bold text-indigo-900 uppercase tracking-widest text-left">
                {t('dream_interpreter_desc')}
              </span>
            </div>
          </div>

          {/* Chat Area */}
          <div 
            ref={scrollRef}
            className="flex-1 overflow-y-auto p-6 no-scrollbar"
          >
            {messages.length === 0 && (
              <div className="h-full flex flex-col items-center justify-center space-y-8 text-center px-4">
                <div className="w-20 h-20 rounded-full bg-indigo-50 flex items-center justify-center">
                  <Moon className="w-10 h-10 text-indigo-200" />
                </div>
                <div className="space-y-2">
                  <h3 className="text-xl font-serif font-bold text-indigo-900">{t('dream_interpreter_title')}</h3>
                  <p className="text-sm text-gray-400 max-w-[240px]">{t('dream_intro')}</p>
                </div>
              </div>
            )}
            
            {messages.map(m => (
              <MessageBubble key={m.id} message={m} />
            ))}
            
            {isTyping && <TypingIndicator />}
          </div>

          {/* Input Bar */}
          <div className="p-6 bg-white border-t border-black/5">
            <div className={cn(
              "flex items-center space-x-3 bg-gray-50 rounded-[28px] p-2 pl-5 border border-black/5 focus-within:border-indigo-500 transition-colors",
              isRTL && "space-x-reverse pl-2 pr-5"
            )}>
              <input 
                type="text"
                value={inputText}
                onChange={(e) => setInputText(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && handleSend()}
                placeholder={t('dream_placeholder')}
                className="flex-1 bg-transparent border-none outline-none text-sm text-indigo-900 placeholder:text-gray-400"
              />
              <motion.button
                whileTap={{ scale: 0.9 }}
                disabled={!inputText.trim()}
                onClick={() => handleSend()}
                className={cn(
                  "w-10 h-10 rounded-full flex items-center justify-center transition-all",
                  inputText.trim() ? "bg-indigo-600 text-white shadow-lg shadow-indigo-200" : "bg-gray-200 text-gray-400"
                )}
              >
                <Send className={cn("w-5 h-5", isRTL && "rotate-180")} />
              </motion.button>
            </div>
            <p className="text-[8px] text-center text-gray-300 mt-4 uppercase tracking-widest font-bold">
              {t('nisa_disclaimer')}
            </p>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
