import { useCallback, useState, type DragEvent } from 'react';
import { motion } from 'motion/react';
import { Upload } from 'lucide-react';
import { cn } from '../../lib/cn';

export function FileDropzone({
  onFile,
  accept,
  className,
}: {
  onFile: (file: File) => void;
  accept?: string;
  className?: string;
}) {
  const [dragging, setDragging] = useState(false);

  const handleFile = useCallback(
    (file: File | undefined) => {
      if (file) onFile(file);
    },
    [onFile]
  );

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files[0];
    handleFile(file);
  };

  return (
    <motion.label
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
      animate={{
        borderColor: dragging ? '#4F46E5' : '#E5E7EB',
        backgroundColor: dragging ? '#EEF2FF' : '#F8F9FC',
      }}
      transition={{ duration: 0.15 }}
      className={cn(
        'flex cursor-pointer flex-col items-center justify-center rounded-card border-2 border-dashed border-border bg-surface-muted px-6 py-12 text-center transition-colors',
        className
      )}
    >
      <input
        type="file"
        accept={accept}
        className="sr-only"
        onChange={(e) => handleFile(e.target.files?.[0])}
      />
      <motion.div
        animate={{ scale: dragging ? 1.05 : 1 }}
        className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-accent-muted"
      >
        <Upload className="h-6 w-6 text-accent" />
      </motion.div>
      <span className="text-sm font-medium text-text-primary">
        Drop a file here or click to browse
      </span>
      <span className="mt-1 text-xs text-text-secondary">PDF, DOCX, or images up to 10MB</span>
    </motion.label>
  );
}
