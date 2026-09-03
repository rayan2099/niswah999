/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 * PDFReport component using react-pdf toBlob functionality
 */

import React from 'react';
import { Document, Page, Text, View, StyleSheet, Font, Image } from '@react-pdf/renderer';
import { format, parseISO } from 'date-fns';
import { toHijri } from 'hijri-converter';
import { Madhhab } from '../logic/types.ts';
import { DBCycleEntry, DBAdahLedger } from '../api/db-types.ts';

// Register Arabic font for PDF support
Font.register({
  family: 'Cairo',
  fonts: [
    {
      src: 'https://fonts.gstatic.com/s/cairo/v28/SLXGc1nY6HkvalIkTpumxdt0UX8.woff2',
      fontWeight: 400,
    },
    {
      src: 'https://fonts.gstatic.com/s/cairo/v28/SLXGc1nY6HkvalIkTpumxdt0UX8.woff2',
      fontWeight: 700,
    }
  ]
});

const styles = StyleSheet.create({
  page: {
    padding: 40,
    backgroundColor: '#FFFFFF',
    fontFamily: 'Cairo',
    direction: 'rtl',
  },
  header: {
    marginBottom: 20,
    borderBottom: 1,
    borderBottomColor: '#E5E7EB',
    paddingBottom: 10,
    textAlign: 'right',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#065F46', // Emerald 900
    textAlign: 'right',
  },
  subtitle: {
    fontSize: 12,
    color: '#6B7280', // Gray 500
    marginTop: 4,
    textAlign: 'right',
  },
  section: {
    marginTop: 20,
    marginBottom: 10,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#065F46',
    marginBottom: 10,
    backgroundColor: '#F0FDF4',
    padding: 4,
    textAlign: 'right',
  },
  table: {
    display: 'flex',
    width: 'auto',
    borderStyle: 'solid',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRightWidth: 0,
    borderBottomWidth: 0,
  },
  tableRow: {
    margin: 'auto',
    flexDirection: 'row-reverse', // For RTL table
  },
  tableColHeader: {
    width: '14.2%',
    borderStyle: 'solid',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderLeftWidth: 0,
    borderTopWidth: 0,
    backgroundColor: '#F9FAFB',
    padding: 5,
  },
  tableCol: {
    width: '14.2%',
    borderStyle: 'solid',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderLeftWidth: 0,
    borderTopWidth: 0,
    padding: 5,
  },
  tableCellHeader: {
    fontSize: 8,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  tableCell: {
    fontSize: 7,
    textAlign: 'center',
  },
  footer: {
    position: 'absolute',
    bottom: 40,
    left: 40,
    right: 40,
    fontSize: 8,
    color: '#9CA3AF',
    textAlign: 'center',
    borderTop: 1,
    borderTopColor: '#E5E7EB',
    paddingTop: 10,
  },
  highlight: {
    backgroundColor: '#FEF2F2', // Rose 50
  },
  infoBox: {
    padding: 10,
    backgroundColor: '#F3F4F6',
    borderRadius: 4,
    marginTop: 10,
    textAlign: 'right',
  },
  infoText: {
    fontSize: 10,
    color: '#374151',
    lineHeight: 1.4,
    textAlign: 'right',
  }
});

interface FiqhReportProps {
  user: any;
  ledger: DBAdahLedger[];
  fiqhState?: string;
  t: (key: any, params?: any) => string;
}

export const FiqhReport = ({ user, ledger = [], fiqhState = 'TAHARA', t }: FiqhReportProps) => {
  const displayName = user?.anonymous_mode ? (user?.language === 'ar' ? "أخت" : "Sister") : (user?.display_name || user?.name || (user?.language === 'ar' ? "أخت" : "Sister"));
  const madhhabKey = `madhhab_full_${user?.madhhab?.toLowerCase() || 'hanafi'}`;
  const madhhabFull = t(madhhabKey as any);
  const fiqhNoteKey = `fiqh_note_${user?.madhhab?.toLowerCase() || 'hanafi'}`;
  
  const getHijri = (dateStr: string | null | undefined) => {
    if (!dateStr) return '';
    try {
      const date = dateStr === 'now' ? new Date() : parseISO(dateStr);
      const hijri = toHijri(date.getFullYear(), date.getMonth() + 1, date.getDate());
      return `${hijri.hd}/${hijri.hm}/${hijri.hy}`;
    } catch (e) {
      return '';
    }
  };

  const last6Cycles = [...(ledger || [])].sort((a, b) => new Date(b?.haid_start || 0).getTime() - new Date(a?.haid_start || 0).getTime()).slice(0, 6);
  
  // Calculate averages from ledger
  const starts = [...new Set((ledger || []).map(item => new Date(item?.haid_start || '').getTime()))]
    .filter(value => Number.isFinite(value))
    .sort((a, b) => a - b);
  const intervals = starts.slice(1).map((start, index) =>
    Math.round((start - starts[index]) / (24 * 60 * 60 * 1000))
  ).filter(days => days > 0);
  const avgCycleLength = intervals.length > 0
    ? (intervals.reduce((sum, days) => sum + days, 0) / intervals.length).toFixed(1)
    : t('insufficient_data_for_calculation');
    
  const avgHaidDuration = (ledger || []).length > 0 
    ? ((ledger || []).reduce((acc, curr) => acc + (curr?.haid_duration_hours || 0), 0) / (ledger || []).length / 24).toFixed(1) 
    : (user?.avg_period_duration || '7');
    
  const isRegular = (ledger || []).length > 1; 

  return (
    <Document title={t('fiqh_report_title')}>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title}>نسوة | Niswah</Text>
          <Text style={styles.subtitle}>{t('fiqh_report_title')}</Text>
          <Text style={styles.subtitle}>{t('generated_date')}: {getHijri('now')} هـ | {format(new Date(), 'yyyy-MM-dd')} م</Text>
          <Text style={styles.subtitle}>{t('user')}: {displayName}</Text>
          <Text style={styles.subtitle}>{madhhabFull}</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('menstrual_pattern')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('avg_cycle_length')}: {avgCycleLength} {t('days')}</Text>
            <Text style={styles.infoText}>{t('avg_period_duration')}: {avgHaidDuration} {t('days')}</Text>
            <Text style={styles.infoText}>{t('cycle_regularity')}: {isRegular ? t('regular') : t('irregular')}</Text>
          </View>
          
          <View style={[styles.table, { marginTop: 10 }]}>
            <View style={styles.tableRow}>
              <View style={[styles.tableColHeader, { width: '25%' }]}><Text style={styles.tableCellHeader}>{t('hijri_start')}</Text></View>
              <View style={[styles.tableColHeader, { width: '25%' }]}><Text style={styles.tableCellHeader}>{t('duration')}</Text></View>
              <View style={[styles.tableColHeader, { width: '25%' }]}><Text style={styles.tableCellHeader}>{t('blood_description')}</Text></View>
              <View style={[styles.tableColHeader, { width: '25%' }]}><Text style={styles.tableCellHeader}>{t('tahara_duration')}</Text></View>
            </View>
            {(last6Cycles || []).map((record, i) => (
              <View key={record?.id ?? i} style={[styles.tableRow, record?.istihadah_episode ? styles.highlight : {}]}>
                <View style={[styles.tableCol, { width: '25%' }]}><Text style={styles.tableCell}>{getHijri(record?.haid_start)}</Text></View>
                <View style={[styles.tableCol, { width: '25%' }]}><Text style={styles.tableCell}>{((record?.haid_duration_hours ?? 0) / 24).toFixed(1)} {t('days')}</Text></View>
                <View style={[styles.tableCol, { width: '25%' }]}><Text style={styles.tableCell}>{record?.istihadah_episode ? t('istihadah') : t('haid')}</Text></View>
                <View style={[styles.tableCol, { width: '25%' }]}><Text style={styles.tableCell}>{(record?.tuhr_duration_days || 0).toFixed(1)} {t('days')}</Text></View>
              </View>
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('current_fiqh_status')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('current_state')}: {t(fiqhState?.toLowerCase() ?? 'tahara')}</Text>
            <Text style={styles.infoText}>{t('day_x_of_cycle', { x: user?.current_cycle_day || '1' })}</Text>
            <Text style={styles.infoText}>{t('next_expected_period')}: {user?.next_period_date ? `${getHijri(user.next_period_date)} هـ (${user.next_period_date} م)` : '...'}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('fiqh_notes')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t(fiqhNoteKey as any)}</Text>
          </View>
        </View>

        <Text style={styles.footer}>{t('report_footer_fiqh')}</Text>
      </Page>
    </Document>
  );
};

interface DoctorReportProps {
  user: any;
  stats: any;
  ledger: DBAdahLedger[];
  t: (key: any, params?: any) => string;
}

export const DoctorReport = ({ user, stats, ledger = [], t }: DoctorReportProps) => {
  const displayName = user?.anonymous_mode ? (user?.language === 'ar' ? "أخت" : "Sister") : (user?.display_name || user?.name || (user?.language === 'ar' ? "أخت" : "Sister"));
  const age = user?.birth_year ? new Date().getFullYear() - user.birth_year : '...';
  const last6Cycles = [...(ledger || [])].sort((a, b) => new Date(b?.haid_start || 0).getTime() - new Date(a?.haid_start || 0).getTime()).slice(0, 6);
  const istihadahCount = (ledger || []).filter((l: any) => l?.istihadah_episode).length;

  return (
    <Document title={t('doctor_report_title')}>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title}>نسوة | Niswah</Text>
          <Text style={styles.subtitle}>{t('doctor_report_title')}</Text>
          <Text style={styles.subtitle}>{t('patient')}: {displayName}</Text>
          <Text style={styles.subtitle}>{t('generated_date')}: {format(new Date(), 'yyyy-MM-dd')} | {t('age')}: {age}</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('cycle_summary')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('avg_cycle_length')}: {stats?.avgCycleLength ?? t('insufficient_data_for_calculation')}</Text>
            <Text style={styles.infoText}>{t('avg_period_duration')}: {stats?.avgHaidDuration || user?.avg_period_duration || '7'} {t('days')}</Text>
            <Text style={styles.infoText}>{t('regularity_score')}: {stats?.regularityScore || ((ledger || []).length > 1 ? t('high_regularity') : t('medium_regularity'))}</Text>
            <Text style={styles.infoText}>{t('shortest_cycle')}: {stats?.shortestCycle || '...'} {t('days')} | {t('longest_cycle')}: {stats?.longestCycle || '...'} {t('days')}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('cycle_history')}</Text>
          <View style={styles.table}>
            <View style={styles.tableRow}>
              <View style={[styles.tableColHeader, { width: '20%' }]}><Text style={styles.tableCellHeader}>{t('start')}</Text></View>
              <View style={[styles.tableColHeader, { width: '20%' }]}><Text style={styles.tableCellHeader}>{t('end')}</Text></View>
              <View style={[styles.tableColHeader, { width: '20%' }]}><Text style={styles.tableCellHeader}>{t('duration')}</Text></View>
              <View style={[styles.tableColHeader, { width: '20%' }]}><Text style={styles.tableCellHeader}>{t('flow_intensity')}</Text></View>
              <View style={[styles.tableColHeader, { width: '20%' }]}><Text style={styles.tableCellHeader}>{t('fiqh_notes')}</Text></View>
            </View>
            {(last6Cycles || []).map((record: any, i: number) => (
              <View key={record?.id ?? i} style={styles.tableRow}>
                <View style={[styles.tableCol, { width: '20%' }]}><Text style={styles.tableCell}>{record?.haid_start}</Text></View>
                <View style={[styles.tableCol, { width: '20%' }]}><Text style={styles.tableCell}>{record?.haid_end || '...'}</Text></View>
                <View style={[styles.tableCol, { width: '20%' }]}><Text style={styles.tableCell}>{((record?.haid_duration_hours ?? 0) / 24).toFixed(1)} {t('days')}</Text></View>
                <View style={[styles.tableCol, { width: '20%' }]}><Text style={styles.tableCell}>{t('medium')}</Text></View>
                <View style={[styles.tableCol, { width: '20%' }]}><Text style={styles.tableCell}>{record?.istihadah_episode ? t('istihadah') : t('haid')}</Text></View>
              </View>
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('symptom_trends')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>- {t('mood_pattern_detected')}</Text>
            <Text style={styles.infoText}>- {t('energy_boost_expected')}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('clinical_notes')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>- {istihadahCount > 0 ? `${istihadahCount} ${t('istihadah_episodes')}` : t('no_symptoms_logged')}</Text>
            <Text style={styles.infoText}>- {ledger.length > 1 && !stats?.isRegular ? t('irregular') : t('regular')}</Text>
          </View>
        </View>

        <Text style={styles.footer}>{t('report_footer_doctor')}</Text>
      </Page>
    </Document>
  );
};

interface HusbandReportProps {
  user: {
    id?: string;
    display_name?: string;
    madhhab?: string;
    anonymous_mode?: boolean;
    trying_to_conceive?: boolean;
    language?: string;
  };
  currentDay?: number | null;
  fiqhState?: string;
  nextPeriodDate?: string | Date | null;
  fertilityStart?: string | Date | null;
  fertilityEnd?: string | Date | null;
  t: (key: any, params?: any) => string;
}

export const HusbandReport = ({
  user,
  currentDay = null,
  fiqhState = 'TAHARA',
  nextPeriodDate = null,
  fertilityStart = null,
  fertilityEnd = null,
  t,
}: HusbandReportProps) => {
  const name = user?.anonymous_mode ? (user?.language === 'ar' ? 'أخت' : 'Sister') : (user?.display_name ?? (user?.language === 'ar' ? 'أخت' : 'Sister'));
  const safeNextPeriod = nextPeriodDate
    ? format(new Date(nextPeriodDate), 'dd/MM/yyyy')
    : (user?.language === 'ar' ? 'غير محدد بعد' : 'Not determined yet');
  const safeFertilityStart = fertilityStart
    ? format(new Date(fertilityStart), 'dd/MM/yyyy')
    : null;
  const safeFertilityEnd = fertilityEnd
    ? format(new Date(fertilityEnd), 'dd/MM/yyyy')
    : null;

  return (
    <Document title={t('husband_report_title')}>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title}>نسوة | Niswah</Text>
          <Text style={styles.subtitle}>{t('husband_report_title')}</Text>
          <Text style={styles.subtitle}>{format(new Date(), 'yyyy-MM-dd')}</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('current_state')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('state')}: {t(fiqhState?.toLowerCase() || 'tahara')}</Text>
            <Text style={styles.infoText}>{currentDay === null ? t('insufficient_data_for_calculation') : t('day_x_of_cycle', { x: currentDay })}</Text>
            <Text style={styles.infoText}>{t('expected_end')}: {safeNextPeriod}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('upcoming_days')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('next_expected_period')}: {safeNextPeriod}</Text>
            <Text style={styles.infoText}>{t('fertility_window')}: {safeFertilityStart ? `${safeFertilityStart} - ${safeFertilityEnd || '...'}` : '...'}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('religious_note')}</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>{t('husband_religious_note')}</Text>
          </View>
        </View>

        <Text style={styles.footer}>{t('report_footer_husband')}</Text>
      </Page>
    </Document>
  );
};
